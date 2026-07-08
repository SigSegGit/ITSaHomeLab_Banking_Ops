#!/usr/bin/env bash
# End-to-end smoke test against a REAL running ledger-service + real
# Postgres — no mocks. Asserts account creation, deposit/withdraw/
# transfer arithmetic, insufficient-funds rejection, 404s, /metrics,
# and — the one that actually matters for a "banking" service — that
# 50 concurrent deposits to the same account land on the exact right
# final balance (proves the atomic SQL-side increment, not a Python
# read-modify-write that would lose updates under real concurrency).
#
# Usage: BASE_URL=http://127.0.0.1:8000 ./smoke-e2e.sh
# Expects the service and its Postgres to already be running (either
# `docker compose up` or the app pointed at a local Postgres).

set -uo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"
FAILURES=0

fail() { echo "  FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "  ok: $1"; }

assert_eq() {
    local actual="$1" expected="$2" desc="$3"
    if [ "$actual" = "$expected" ]; then
        pass "$desc"
    else
        fail "$desc (expected [$expected], got [$actual])"
    fi
}

echo "==> waiting for $BASE_URL/health"
waited=0
until curl -s -o /dev/null "$BASE_URL/health"; do
    sleep 0.5
    waited=$((waited + 1))
    if [ "$waited" -gt 60 ]; then
        fail "service never answered /health"
        echo "==> smoke-e2e FAILED: $FAILURES check(s) failed"
        exit 1
    fi
done

echo "==> account creation, deposit, withdraw, transfer arithmetic"
alice=$(curl -s -X POST "$BASE_URL/accounts" -H 'Content-Type: application/json' -d '{"owner_name":"Alice"}')
alice_id=$(echo "$alice" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
bob=$(curl -s -X POST "$BASE_URL/accounts" -H 'Content-Type: application/json' -d '{"owner_name":"Bob"}')
bob_id=$(echo "$bob" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

curl -s -X POST "$BASE_URL/accounts/$alice_id/deposit" -H 'Content-Type: application/json' -d '{"amount_cents":10000}' >/dev/null
curl -s -X POST "$BASE_URL/accounts/$alice_id/withdraw" -H 'Content-Type: application/json' -d '{"amount_cents":3000}' >/dev/null

code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/accounts/$alice_id/withdraw" \
    -H 'Content-Type: application/json' -d '{"amount_cents":999999}')
assert_eq "$code" "400" "withdrawing more than the balance is rejected"

curl -s -X POST "$BASE_URL/transfer" -H 'Content-Type: application/json' \
    -d "{\"from_account_id\":\"$alice_id\",\"to_account_id\":\"$bob_id\",\"amount_cents\":5000}" >/dev/null

alice_balance=$(curl -s "$BASE_URL/accounts/$alice_id" | python3 -c "import sys,json; print(json.load(sys.stdin)['balance_cents'])")
assert_eq "$alice_balance" "2000" "Alice's balance is 10000-3000-5000=2000 after deposit/withdraw/transfer"

bob_balance=$(curl -s "$BASE_URL/accounts/$bob_id" | python3 -c "import sys,json; print(json.load(sys.stdin)['balance_cents'])")
assert_eq "$bob_balance" "5000" "Bob received the transferred 5000"

tx_count=$(curl -s "$BASE_URL/accounts/$alice_id/transactions" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
assert_eq "$tx_count" "3" "Alice has exactly 3 transaction records (deposit, withdrawal, transfer_out)"

code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/accounts/00000000-0000-0000-0000-000000000000")
assert_eq "$code" "404" "an unknown account id returns 404"

echo "==> /metrics is scrapable"
metrics_lines=$(curl -s "$BASE_URL/metrics" | grep -c "^http_request")
if [ "$metrics_lines" -gt 0 ]; then
    pass "/metrics exposes http_request* series for Prometheus"
else
    fail "/metrics did not expose any http_request* series"
fi

echo "==> 50 concurrent deposits land on the exact right balance (no lost updates)"
concurrency=$(curl -s -X POST "$BASE_URL/accounts" -H 'Content-Type: application/json' -d '{"owner_name":"ConcurrencyTest"}')
concurrency_id=$(echo "$concurrency" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
for _ in $(seq 1 50); do
    curl -s -o /dev/null -X POST "$BASE_URL/accounts/$concurrency_id/deposit" \
        -H 'Content-Type: application/json' -d '{"amount_cents":100}' &
done
wait
final_balance=$(curl -s "$BASE_URL/accounts/$concurrency_id" | python3 -c "import sys,json; print(json.load(sys.stdin)['balance_cents'])")
assert_eq "$final_balance" "5000" "50 concurrent 100-cent deposits sum to exactly 5000"

if [ "$FAILURES" -eq 0 ]; then
    echo "==> smoke-e2e OK (all checks passed)"
else
    echo "==> smoke-e2e FAILED: $FAILURES check(s) failed"
    exit 1
fi
