"""
Order Processor — SQS Integration Router

Provides an API endpoint for submitting orders that are
buffered via Amazon SQS for async processing.
"""

import json
import logging
import os

import boto3
from fastapi import APIRouter, BackgroundTasks, HTTPException

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/orders", tags=["orders"])

# Lazy-init SQS client to avoid errors when SQS_QUEUE_URL is not set (e.g., in tests)
_sqs_client = None


def _get_sqs_client():
    global _sqs_client
    if _sqs_client is None:
        _sqs_client = boto3.client("sqs")
    return _sqs_client


QUEUE_URL = os.getenv("SQS_QUEUE_URL", "")


@router.post("")
async def create_order(order_data: dict, background_tasks: BackgroundTasks):
    """Submit an order for async processing via SQS."""
    if not QUEUE_URL:
        raise HTTPException(status_code=503, detail="Order processing is not configured")

    background_tasks.add_task(_send_to_sqs, order_data)
    logger.info("Order queued for processing", extra={"order_keys": list(order_data.keys())})
    return {"message": "Order received and queued for processing"}


def _send_to_sqs(data: dict) -> None:
    """Send order data to SQS queue."""
    try:
        _get_sqs_client().send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=json.dumps(data),
        )
        logger.info("Order sent to SQS successfully")
    except Exception:
        logger.exception("Failed to send order to SQS")
