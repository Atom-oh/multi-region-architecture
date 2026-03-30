"""
ElastiCache Global Replication Group Failover Lambda Function

Triggered by EventBridge when Route53 health check alarms go to ALARM state.
Promotes the secondary ElastiCache replication group to primary.
"""

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
GLOBAL_REPLICATION_GROUP_ID = os.environ.get("GLOBAL_REPLICATION_GROUP_ID")
TARGET_REGION = os.environ.get("TARGET_REGION")
TARGET_REPLICATION_GROUP_ID = os.environ.get("TARGET_REPLICATION_GROUP_ID")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")
ENABLE_AUTO_FAILOVER = os.environ.get("ENABLE_AUTO_FAILOVER", "false").lower() == "true"

# AWS clients
elasticache_client = boto3.client("elasticache")
sns_client = boto3.client("sns")


def send_notification(subject: str, message: str) -> None:
    """Send notification to SNS topic."""
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject[:100],  # SNS subject limit
            Message=message,
        )
        logger.info(f"Notification sent: {subject}")
    except ClientError as e:
        logger.error(f"Failed to send notification: {e}")


def get_global_replication_group_status() -> dict:
    """Get current status of the global replication group."""
    try:
        response = elasticache_client.describe_global_replication_groups(
            GlobalReplicationGroupId=GLOBAL_REPLICATION_GROUP_ID,
            ShowMemberInfo=True,
        )
        if response["GlobalReplicationGroups"]:
            return response["GlobalReplicationGroups"][0]
        return {}
    except ClientError as e:
        logger.error(f"Failed to describe global replication group: {e}")
        return {}


def perform_failover() -> dict:
    """Execute failover to the target replication group."""
    try:
        logger.info(
            f"Initiating failover of global replication group {GLOBAL_REPLICATION_GROUP_ID} "
            f"to {TARGET_REPLICATION_GROUP_ID} in {TARGET_REGION}"
        )

        response = elasticache_client.failover_global_replication_group(
            GlobalReplicationGroupId=GLOBAL_REPLICATION_GROUP_ID,
            PrimaryRegion=TARGET_REGION,
            PrimaryReplicationGroupId=TARGET_REPLICATION_GROUP_ID,
        )

        logger.info(f"Failover initiated successfully: {response}")
        return {
            "status": "success",
            "message": f"Failover initiated to {TARGET_REPLICATION_GROUP_ID} in {TARGET_REGION}",
            "response": str(response),
        }

    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        error_message = e.response["Error"]["Message"]
        logger.error(f"Failover failed: {error_code} - {error_message}")
        return {
            "status": "error",
            "message": f"Failover failed: {error_code} - {error_message}",
        }


def handler(event: dict, context) -> dict:
    """
    Lambda handler for ElastiCache failover.

    Args:
        event: EventBridge event containing CloudWatch alarm details
        context: Lambda context

    Returns:
        Response dict with status and message
    """
    logger.info(f"Received event: {json.dumps(event)}")

    # Validate configuration
    if not all(
        [
            GLOBAL_REPLICATION_GROUP_ID,
            TARGET_REGION,
            TARGET_REPLICATION_GROUP_ID,
            SNS_TOPIC_ARN,
        ]
    ):
        error_msg = "Missing required environment variables"
        logger.error(error_msg)
        return {"statusCode": 500, "body": error_msg}

    # Extract alarm details from event
    alarm_name = event.get("detail", {}).get("alarmName", "Unknown")
    alarm_state = event.get("detail", {}).get("state", {}).get("value", "Unknown")
    alarm_reason = event.get("detail", {}).get("state", {}).get("reason", "Unknown")

    logger.info(f"Processing alarm: {alarm_name}, state: {alarm_state}")

    # Check current global replication group status
    group_status = get_global_replication_group_status()
    if not group_status:
        error_msg = (
            f"Could not retrieve global replication group status for "
            f"{GLOBAL_REPLICATION_GROUP_ID}"
        )
        logger.error(error_msg)
        send_notification("ElastiCache DR - Status Check Failed", error_msg)
        return {"statusCode": 500, "body": error_msg}

    current_status = group_status.get("Status", "unknown")
    logger.info(f"Current global replication group status: {current_status}")

    # Check if group is already failing over
    if current_status in ["modifying", "failing-over"]:
        msg = (
            f"Global replication group {GLOBAL_REPLICATION_GROUP_ID} "
            f"is already in {current_status} state"
        )
        logger.info(msg)
        send_notification("ElastiCache DR - Failover Already In Progress", msg)
        return {"statusCode": 200, "body": msg}

    # Check if auto-failover is enabled
    if not ENABLE_AUTO_FAILOVER:
        msg = (
            f"Auto-failover is DISABLED. Manual intervention required.\n\n"
            f"Alarm: {alarm_name}\n"
            f"State: {alarm_state}\n"
            f"Reason: {alarm_reason}\n\n"
            f"To manually failover, run:\n"
            f"aws elasticache failover-global-replication-group "
            f"--global-replication-group-id {GLOBAL_REPLICATION_GROUP_ID} "
            f"--primary-region {TARGET_REGION} "
            f"--primary-replication-group-id {TARGET_REPLICATION_GROUP_ID}"
        )
        logger.info(msg)
        send_notification("ElastiCache DR - Manual Failover Required", msg)
        return {"statusCode": 200, "body": msg}

    # Perform failover
    result = perform_failover()

    if result["status"] == "success":
        send_notification(
            "ElastiCache DR - Failover Initiated",
            f"Successfully initiated failover of {GLOBAL_REPLICATION_GROUP_ID} "
            f"to {TARGET_REPLICATION_GROUP_ID} in {TARGET_REGION}.\n\n"
            f"Triggered by alarm: {alarm_name}\n"
            f"Reason: {alarm_reason}\n\n"
            f"Monitor progress in the AWS Console.",
        )
        return {"statusCode": 200, "body": result["message"]}
    else:
        send_notification(
            "ElastiCache DR - Failover Failed",
            f"Failed to failover {GLOBAL_REPLICATION_GROUP_ID}.\n\n"
            f"Error: {result['message']}\n\n"
            f"Manual intervention required.",
        )
        return {"statusCode": 500, "body": result["message"]}
