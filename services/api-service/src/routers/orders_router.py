"""
Orders Router — CRUD with database persistence + optional SQS dispatch
"""

import json
import logging
import math
import os

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from src.database import get_db
from src.models import Order, User
from src.routers.auth_router import get_current_user
from src.schemas import (
    OrderCreateRequest,
    OrderResponse,
    OrderUpdateRequest,
    PaginatedOrders,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/orders", tags=["orders"])

QUEUE_URL = os.getenv("SQS_QUEUE_URL", "")
_sqs_client = None


def _get_sqs():
    global _sqs_client
    if _sqs_client is None:
        import boto3
        _sqs_client = boto3.client("sqs")
    return _sqs_client


def _dispatch_to_sqs(order_id: str, data: dict) -> None:
    if not QUEUE_URL:
        return
    try:
        _get_sqs().send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps({"order_id": order_id, **data}))
        logger.info("Order dispatched to SQS", extra={"order_id": order_id})
    except Exception:
        logger.exception("SQS dispatch failed — order persisted in DB", extra={"order_id": order_id})


@router.get("", response_model=PaginatedOrders)
async def list_orders(
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
    status_filter: str | None = Query(None, alias="status"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List orders for the authenticated user, with optional status filter."""
    base_q = select(Order).where(Order.user_id == current_user.id)
    if status_filter:
        base_q = base_q.where(Order.status == status_filter)

    count_result = await db.execute(select(func.count()).select_from(base_q.subquery()))
    total = count_result.scalar_one()

    orders_result = await db.execute(
        base_q.order_by(Order.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    orders = orders_result.scalars().all()

    return PaginatedOrders(
        items=orders,
        total=total,
        page=page,
        page_size=page_size,
        total_pages=max(1, math.ceil(total / page_size)),
    )


@router.post("", response_model=OrderResponse, status_code=status.HTTP_201_CREATED)
async def create_order(
    payload: OrderCreateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a new order for the authenticated user."""
    order = Order(
        user_id=current_user.id,
        product_name=payload.product_name,
        quantity=payload.quantity,
        unit_price=payload.unit_price,
        notes=payload.notes,
        status="pending",
    )
    db.add(order)
    await db.commit()
    await db.refresh(order)

    _dispatch_to_sqs(order.id, {"product_name": payload.product_name, "quantity": payload.quantity})
    logger.info("Order created", extra={"order_id": order.id, "user_id": current_user.id})
    return order


@router.get("/{order_id}", response_model=OrderResponse)
async def get_order(
    order_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Order).where(Order.id == order_id, Order.user_id == current_user.id)
    )
    order = result.scalar_one_or_none()
    if order is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")
    return order


@router.put("/{order_id}", response_model=OrderResponse)
async def update_order_status(
    order_id: str,
    payload: OrderUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Order).where(Order.id == order_id, Order.user_id == current_user.id)
    )
    order = result.scalar_one_or_none()
    if order is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")

    order.status = payload.status
    await db.commit()
    await db.refresh(order)
    return order


@router.delete("/{order_id}", status_code=status.HTTP_204_NO_CONTENT)
async def cancel_order(
    order_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Order).where(Order.id == order_id, Order.user_id == current_user.id)
    )
    order = result.scalar_one_or_none()
    if order is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")
    if order.status == "cancelled":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Order already cancelled")

    order.status = "cancelled"
    await db.commit()
