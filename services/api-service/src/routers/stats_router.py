"""
Stats Router — Dashboard analytics for the current user
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from src.database import get_db
from src.models import Order, User
from src.routers.auth_router import get_current_user
from src.schemas import StatsResponse

router = APIRouter(prefix="/api/stats", tags=["stats"])


@router.get("", response_model=StatsResponse)
async def get_stats(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Return dashboard statistics for the authenticated user."""
    now = datetime.now(timezone.utc)
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    # Counts by status
    status_rows = await db.execute(
        select(Order.status, func.count(Order.id))
        .where(Order.user_id == current_user.id)
        .group_by(Order.status)
    )
    counts = {row[0]: row[1] for row in status_rows.all()}

    # Revenue (completed orders only)
    revenue_row = await db.execute(
        select(func.sum(Order.quantity * Order.unit_price))
        .where(Order.user_id == current_user.id, Order.status == "completed")
    )
    total_revenue = float(revenue_row.scalar_one() or 0.0)

    # This month
    month_count_row = await db.execute(
        select(func.count(Order.id))
        .where(Order.user_id == current_user.id, Order.created_at >= month_start)
    )
    month_revenue_row = await db.execute(
        select(func.sum(Order.quantity * Order.unit_price))
        .where(
            Order.user_id == current_user.id,
            Order.status == "completed",
            Order.created_at >= month_start,
        )
    )

    return StatsResponse(
        total_orders=sum(counts.values()),
        pending=counts.get("pending", 0),
        processing=counts.get("processing", 0),
        completed=counts.get("completed", 0),
        cancelled=counts.get("cancelled", 0),
        total_revenue=round(total_revenue, 2),
        this_month_orders=month_count_row.scalar_one() or 0,
        this_month_revenue=round(float(month_revenue_row.scalar_one() or 0.0), 2),
    )
