import datetime
import uuid

from sqlalchemy import Column, DateTime, ForeignKey, Numeric, String
from sqlalchemy.dialects.postgresql import UUID

from .db import Base


class Account(Base):
    __tablename__ = "accounts"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_name = Column(String, nullable=False)
    balance_cents = Column(Numeric(20, 0), nullable=False, default=0)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)


class Transaction(Base):
    __tablename__ = "transactions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    account_id = Column(UUID(as_uuid=True), ForeignKey("accounts.id"), nullable=False)
    kind = Column(String, nullable=False)  # deposit | withdrawal | transfer_in | transfer_out
    amount_cents = Column(Numeric(20, 0), nullable=False)
    counterparty_account_id = Column(UUID(as_uuid=True), nullable=True)
    resulting_balance_cents = Column(Numeric(20, 0), nullable=False)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)
