"""
Pydantic Schemas — Request/Response models
"""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, EmailStr, Field, field_validator


# ─────────────────────────── Auth ───────────────────────────

class RegisterRequest(BaseModel):
    full_name: str = Field(..., min_length=2, max_length=100)
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)

    @field_validator("full_name")
    @classmethod
    def name_no_special(cls, v: str) -> str:
        if not all(c.isalpha() or c.isspace() or c in "-'" for c in v):
            raise ValueError("Full name contains invalid characters")
        return v.strip()


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


# ─────────────────────────── User ───────────────────────────

class UserResponse(BaseModel):
    id: str
    email: str
    full_name: str
    is_active: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class UserUpdateRequest(BaseModel):
    full_name: str | None = Field(None, min_length=2, max_length=100)
    email: EmailStr | None = None


# ─────────────────────────── Orders ─────────────────────────

OrderStatus = Literal["pending", "processing", "completed", "cancelled"]

DEMO_PRODUCTS = [
    ("Enterprise SSD 1TB", 2, 149.99),
    ("Cloud Storage Plan Pro", 1, 299.00),
    ("Network Switch 48-Port", 3, 499.50),
    ("Server Rack Unit", 1, 1200.00),
    ("UPS Battery Backup", 2, 389.75),
    ("Fiber Optic Cable 100m", 5, 89.99),
    ("GPU Compute Node", 1, 3499.00),
    ("RAM DDR5 64GB", 4, 219.99),
]


class OrderCreateRequest(BaseModel):
    product_name: str = Field(..., min_length=2, max_length=255)
    quantity: int = Field(..., ge=1, le=10000)
    unit_price: float = Field(..., ge=0.0)
    notes: str | None = Field(None, max_length=1000)


class OrderResponse(BaseModel):
    id: str
    user_id: str
    product_name: str
    quantity: int
    unit_price: float
    total_amount: float
    status: str
    notes: str | None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class OrderUpdateRequest(BaseModel):
    status: OrderStatus


# ─────────────────────────── Stats ──────────────────────────

class StatsResponse(BaseModel):
    total_orders: int
    pending: int
    processing: int
    completed: int
    cancelled: int
    total_revenue: float
    this_month_orders: int
    this_month_revenue: float


# ─────────────────────────── Pagination ─────────────────────

class PaginatedOrders(BaseModel):
    items: list[OrderResponse]
    total: int
    page: int
    page_size: int
    total_pages: int
