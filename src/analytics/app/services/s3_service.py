"""S3 service for storing analytics events."""

import json
import logging
from datetime import datetime
from typing import TYPE_CHECKING

import boto3
from botocore.exceptions import ClientError

if TYPE_CHECKING:
    from ..models.analytics import EventRecord

logger = logging.getLogger(__name__)


class S3Service:
    def __init__(self, bucket: str, prefix: str = "events/"):
        self.bucket = bucket
        self.prefix = prefix
        self.client = boto3.client("s3")

    async def write_events(self, events: list["EventRecord"]) -> int:
        """Write events to S3 as JSON lines."""
        if not events:
            return 0

        timestamp = datetime.utcnow().strftime("%Y/%m/%d/%H")
        key = f"{self.prefix}{timestamp}/{datetime.utcnow().isoformat()}.jsonl"

        # Convert events to JSON lines
        lines = []
        for event in events:
            try:
                line = json.dumps(event.model_dump(), default=str)
                lines.append(line)
            except Exception as e:
                logger.error(f"Failed to serialize event: {e}")

        if not lines:
            return 0

        content = "\n".join(lines)

        try:
            self.client.put_object(
                Bucket=self.bucket,
                Key=key,
                Body=content.encode("utf-8"),
                ContentType="application/x-ndjson",
            )
            logger.info(f"Wrote {len(lines)} events to s3://{self.bucket}/{key}")
            return len(lines)
        except ClientError as e:
            logger.error(f"Failed to write to S3: {e}")
            return 0

    async def query_events(
        self,
        prefix: str,
        start_time: datetime,
        end_time: datetime,
    ) -> list[dict]:
        """Query events from S3 within a time range."""
        events = []

        try:
            # List objects with the given prefix
            paginator = self.client.get_paginator("list_objects_v2")

            for page in paginator.paginate(Bucket=self.bucket, Prefix=f"{self.prefix}{prefix}"):
                for obj in page.get("Contents", []):
                    # Check if object is within time range based on key
                    response = self.client.get_object(Bucket=self.bucket, Key=obj["Key"])
                    content = response["Body"].read().decode("utf-8")

                    for line in content.strip().split("\n"):
                        if line:
                            try:
                                event = json.loads(line)
                                event_time = datetime.fromisoformat(
                                    event.get("timestamp", "").replace("Z", "+00:00")
                                )
                                if start_time <= event_time <= end_time:
                                    events.append(event)
                            except (json.JSONDecodeError, ValueError):
                                continue

        except ClientError as e:
            logger.error(f"Failed to query S3: {e}")

        return events
