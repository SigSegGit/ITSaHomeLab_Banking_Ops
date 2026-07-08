import uuid

from fastapi import Depends, FastAPI, HTTPException
from prometheus_fastapi_instrumentator import Instrumentator
from sqlalchemy import update
from sqlalchemy.orm import Session

from . import models, schemas
from .db import Base, SessionLocal, engine, get_db

app = FastAPI(title="ITSaHomeLab ledger service")
Instrumentator().instrument(app).expose(app)


@app.on_event("startup")
def create_tables():
    Base.metadata.create_all(bind=engine)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/accounts", response_model=schemas.AccountOut, status_code=201)
def create_account(payload: schemas.AccountCreate, db: Session = Depends(get_db)):
    account = models.Account(owner_name=payload.owner_name, balance_cents=0)
    db.add(account)
    db.commit()
    db.refresh(account)
    return account


@app.get("/accounts/{account_id}", response_model=schemas.AccountOut)
def get_account(account_id: uuid.UUID, db: Session = Depends(get_db)):
    account = db.get(models.Account, account_id)
    if account is None:
        raise HTTPException(status_code=404, detail="account not found")
    return account


@app.get(
    "/accounts/{account_id}/transactions", response_model=list[schemas.TransactionOut]
)
def list_transactions(account_id: uuid.UUID, db: Session = Depends(get_db)):
    account = db.get(models.Account, account_id)
    if account is None:
        raise HTTPException(status_code=404, detail="account not found")
    return (
        db.query(models.Transaction)
        .filter(models.Transaction.account_id == account_id)
        .order_by(models.Transaction.created_at)
        .all()
    )


@app.post("/accounts/{account_id}/deposit", response_model=schemas.AccountOut)
def deposit(
    account_id: uuid.UUID, payload: schemas.AmountRequest, db: Session = Depends(get_db)
):
    account = db.get(models.Account, account_id)
    if account is None:
        raise HTTPException(status_code=404, detail="account not found")

    # Atomic SQL-side increment, not a Python read-modify-write — the
    # latter loses updates under concurrent deposits to the same
    # account (exactly the kind of race a load test would surface).
    db.execute(
        update(models.Account)
        .where(models.Account.id == account_id)
        .values(balance_cents=models.Account.balance_cents + payload.amount_cents)
    )
    db.refresh(account)
    db.add(
        models.Transaction(
            account_id=account_id,
            kind="deposit",
            amount_cents=payload.amount_cents,
            resulting_balance_cents=account.balance_cents,
        )
    )
    db.commit()
    db.refresh(account)
    return account


@app.post("/accounts/{account_id}/withdraw", response_model=schemas.AccountOut)
def withdraw(
    account_id: uuid.UUID, payload: schemas.AmountRequest, db: Session = Depends(get_db)
):
    account = db.get(models.Account, account_id)
    if account is None:
        raise HTTPException(status_code=404, detail="account not found")

    # Atomic conditional decrement: the WHERE clause makes the
    # insufficient-funds check and the debit a single database
    # operation, so two concurrent withdrawals against the same
    # account can't both succeed past a balance neither actually had.
    result = db.execute(
        update(models.Account)
        .where(
            models.Account.id == account_id,
            models.Account.balance_cents >= payload.amount_cents,
        )
        .values(balance_cents=models.Account.balance_cents - payload.amount_cents)
    )
    if result.rowcount == 0:
        db.rollback()
        raise HTTPException(status_code=400, detail="insufficient funds")

    db.refresh(account)
    db.add(
        models.Transaction(
            account_id=account_id,
            kind="withdrawal",
            amount_cents=payload.amount_cents,
            resulting_balance_cents=account.balance_cents,
        )
    )
    db.commit()
    db.refresh(account)
    return account


@app.post("/transfer", response_model=schemas.AccountOut)
def transfer(payload: schemas.TransferRequest, db: Session = Depends(get_db)):
    if payload.from_account_id == payload.to_account_id:
        raise HTTPException(status_code=400, detail="cannot transfer to the same account")

    from_account = db.get(models.Account, payload.from_account_id)
    if from_account is None:
        raise HTTPException(status_code=404, detail="source account not found")
    to_account = db.get(models.Account, payload.to_account_id)
    if to_account is None:
        raise HTTPException(status_code=404, detail="destination account not found")

    result = db.execute(
        update(models.Account)
        .where(
            models.Account.id == payload.from_account_id,
            models.Account.balance_cents >= payload.amount_cents,
        )
        .values(balance_cents=models.Account.balance_cents - payload.amount_cents)
    )
    if result.rowcount == 0:
        db.rollback()
        raise HTTPException(status_code=400, detail="insufficient funds")

    db.execute(
        update(models.Account)
        .where(models.Account.id == payload.to_account_id)
        .values(balance_cents=models.Account.balance_cents + payload.amount_cents)
    )

    db.refresh(from_account)
    db.add(
        models.Transaction(
            account_id=payload.from_account_id,
            kind="transfer_out",
            amount_cents=payload.amount_cents,
            counterparty_account_id=payload.to_account_id,
            resulting_balance_cents=from_account.balance_cents,
        )
    )
    db.refresh(to_account)
    db.add(
        models.Transaction(
            account_id=payload.to_account_id,
            kind="transfer_in",
            amount_cents=payload.amount_cents,
            counterparty_account_id=payload.from_account_id,
            resulting_balance_cents=to_account.balance_cents,
        )
    )
    db.commit()
    db.refresh(from_account)
    return from_account
