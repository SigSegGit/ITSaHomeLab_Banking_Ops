import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class AccountCreate(BaseModel):
    owner_name: str = Field(min_length=1, max_length=200)


class AccountOut(BaseModel):
    id: uuid.UUID
    owner_name: str
    balance_cents: int
    created_at: datetime

    class Config:
        from_attributes = True


class AmountRequest(BaseModel):
    amount_cents: int = Field(gt=0)


class TransferRequest(BaseModel):
    from_account_id: uuid.UUID
    to_account_id: uuid.UUID
    amount_cents: int = Field(gt=0)


class TransactionOut(BaseModel):
    id: uuid.UUID
    account_id: uuid.UUID
    kind: str
    amount_cents: int
    counterparty_account_id: uuid.UUID | None
    resulting_balance_cents: int
    created_at: datetime

    class Config:
        from_attributes = True
