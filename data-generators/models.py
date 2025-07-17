from pydantic import BaseModel
from datetime import datetime
from typing import Optional, Dict, Any
from enum import Enum

class UserTier(str, Enum):
    BRONZE = "bronze"
    SILVER = "silver"
    GOLD = "gold"
    PLATINUM = "platinum"

class TransactionStatus(str, Enum):
    PENDING = "pending"
    COMPLETED = "completed"
    FAILED = "failed"
    REFUNDED = "refunded"

class EventType(str, Enum):
    PAGE_VIEW = "page_view"
    PRODUCT_VIEW = "product_view"
    ADD_TO_CART = "add_to_cart"
    REMOVE_FROM_CART = "remove_from_cart"
    CHECKOUT_START = "checkout_start"
    PURCHASE = "purchase"
    LOGIN = "login"
    LOGOUT = "logout"
    SEARCH = "search"

class User(BaseModel):
    user_id: str
    email: str
    first_name: str
    last_name: str
    date_of_birth: datetime
    registration_date: datetime
    country: str
    city: str
    tier: UserTier
    is_active: bool
    last_login: Optional[datetime]

class Product(BaseModel):
    product_id: str
    name: str
    category: str
    subcategory: str
    price: float
    cost: float
    brand: str
    description: str
    is_active: bool
    created_at: datetime

class Transaction(BaseModel):
    transaction_id: str
    user_id: str
    product_id: str
    quantity: int
    unit_price: float
    total_amount: float
    discount_amount: float
    tax_amount: float
    status: TransactionStatus
    payment_method: str
    shipping_address: str
    created_at: datetime
    updated_at: datetime

class UserEvent(BaseModel):
    event_id: str
    user_id: str
    session_id: str
    event_type: EventType
    timestamp: datetime
    page_url: Optional[str]
    product_id: Optional[str]
    search_query: Optional[str]
    device_type: str
    browser: str
    ip_address: str
    properties: Dict[str, Any] = {}