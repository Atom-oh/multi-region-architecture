"""
DocumentDB Global Cluster Failover Lambda Function

Triggered by EventBridge when Route53 health check alarms go to ALARM state.
Promotes the secondary DocumentDB cluster to primary.
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
GLOBAL_CLUSTER_ID = os.environ.get("GLOBAL_CLUSTER_ID")
TARGET_CLUSTER_ID = os.environ.get("TARGET_CLUSTER_ID")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")
ENABLE_AUTO_FAILOVER = os.environ.get("ENABLE_AUTO_FAILOVER", "false").lower() == "true"

# AWS clients
rds_client = boto3.client("rds")
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


def get_global_cluster_status() -> dict:
    """Get current status of the global cluster."""
    try:
        response = rds_client.describe_global_clusters(
            GlobalClusterIdentifier=GLOBAL_CLUSTER_ID
        )
        if response["GlobalClusters"]:
            return response["GlobalClusters"][0]
        return {}
    except ClientError as e:
        logger.error(f"Failed to describe global cluster: {e}")
        return {}


def perform_failover() -> dict:
    """Execute failover to the target cluster."""
    try:
        logger.info(
            f"Initiating failover of global cluster {GLOBAL_CLUSTER_ID} "
            f"to target cluster {TARGET_CLUSTER_ID}"
        )

        response = rds_client.failover_global_cluster(
            GlobalClusterIdentifier=GLOBAL_CLUSTER_ID,
            TargetDbClusterIdentifier=TARGET_CLUSTER_ID,
        )

        logger.info(f"Failover initiated successfully: {response}")
        return {
            "status": "success",
            "message": f"Failover initiated to {TARGET_CLUSTER_ID}",
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
    Lambda handler for DocumentDB failover.

    Args:
        event: EventBridge event containing CloudWatch alarm details
        context: Lambda context

    Returns:
        Response dict with status and message
    """
    logger.info(f"Received event: {json.dumps(event)}")

    # Validate configuration
    if not all([GLOBAL_CLUSTER_ID, TARGET_CLUSTER_ID, SNS_TOPIC_ARN]):
        error_msg = "Missing required environment variables"
        logger.error(error_msg)
        return {"statusCode": 500, "body": error_msg}

    # Extract alarm details from event
    alarm_name = event.get("detail", {}).get("alarmName", "Unknown")
    alarm_state = event.get("detail", {}).get("state", {}).get("value", "Unknown")
    alarm_reason = event.get("detail", {}).get("state", {}).get("reason", "Unknown")

    logger.info(f"Processing alarm: {alarm_name}, state: {alarm_state}")

    # Check current global cluster status
    cluster_status = get_global_cluster_status()
    if not cluster_status:
        error_msg = f"Could not retrieve global cluster status for {GLOBAL_CLUSTER_ID}"
        logger.error(error_msg)
        send_notification("DocumentDB DR - Status Check Failed", error_msg)
        return {"statusCode": 500, "body": error_msg}

    current_status = cluster_status.get("Status", "unknown")
    logger.info(f"Current global cluster status: {current_status}")

    # Check if cluster is already failing over
    if current_status in ["failing-over", "promoting"]:
        msg = f"Global cluster {GLOBAL_CLUSTER_ID} is already in {current_status} state"
        logger.info(msg)
        send_notification("DocumentDB DR - Failover Already In Progress", msg)
        return {"statusCode": 200, "body": msg}

    # Check if auto-failover is enabled
    if not ENABLE_AUTO_FAILOVER:
        msg = (
            f"Auto-failover is DISABLED. Manual intervention required.\n\n"
            f"Alarm: {alarm_name}\n"
            f"State: {alarm_state}\n"
            f"Reason: {alarm_reason}\n\n"
            f"To manually failover, run:\n"
            f"aws rds failover-global-cluster "
            f"--global-cluster-identifier {GLOBAL_CLUSTER_ID} "
            f"--target-db-cluster-identifier {TARGET_CLUSTER_ID}"
        )
        logger.info(msg)
        send_notification("DocumentDB DR - Manual Failover Required", msg)
        return {"statusCode": 200, "body": msg}

    # Perform failover
    result = perform_failover()

    if result["status"] == "success":
        send_notification(
            "DocumentDB DR - Failover Initiated",
            f"Successfully initiated failover of {GLOBAL_CLUSTER_ID} to {TARGET_CLUSTER_ID}.\n\n"
            f"Triggered by alarm: {alarm_name}\n"
            f"Reason: {alarm_reason}\n\n"
            f"Monitor progress in the AWS Console.",
        )
        return {"statusCode": 200, "body": result["message"]}
    else:
        send_notification(
            "DocumentDB DR - Failover Failed",
            f"Failed to failover {GLOBAL_CLUSTER_ID}.\n\n"
            f"Error: {result['message']}\n\n"
            f"Manual intervention required.",
        )
        return {"statusCode": 500, "body": result["message"]}
