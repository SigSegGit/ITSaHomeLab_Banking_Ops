#!/usr/bin/env python3
"""Ramps request rate against a running ledger-service, on purpose.

This exists to *create* the bottleneck the lab is meant to demonstrate:
run this against the Pi's instance and MorePower's instance side by
side, watch the Grafana dashboard (infra/ansible/roles/monitoring-stack)
and the app's own /metrics — the weakest node should visibly saturate
first, which is the concrete justification for ramping up (more nodes,
or cloud burst capacity) rather than a hand-wavy claim.

Usage:
    python3 load-generator.py --base-url http://itsarevolution.local:8000 \
        --start-rps 2 --max-rps 200 --step-seconds 10 --step-rps 10

Ramps from --start-rps to --max-rps, holding each rate for
--step-seconds before increasing by --step-rps, hitting a random mix of
deposit/withdraw/transfer/balance-read requests against a pre-seeded
pool of accounts (seeded once at startup, not created per-request, so
account-creation cost doesn't skew the read/write load being measured).
"""

import argparse
import asyncio
import random
import sys
import time

import httpx


async def seed_accounts(client: httpx.AsyncClient, count: int) -> list[str]:
    ids = []
    for i in range(count):
        r = await client.post("/accounts", json={"owner_name": f"load-test-{i}"})
        r.raise_for_status()
        account_id = r.json()["id"]
        # Give every seeded account some balance up front so withdraw/
        # transfer requests aren't just bouncing off insufficient-funds
        # rejections once the run gets going.
        await client.post(
            f"/accounts/{account_id}/deposit", json={"amount_cents": 100_000_00}
        )
        ids.append(account_id)
    return ids


async def one_request(client: httpx.AsyncClient, account_ids: list[str]) -> float:
    kind = random.choice(["deposit", "withdraw", "transfer", "read"])
    start = time.monotonic()
    try:
        if kind == "deposit":
            acc = random.choice(account_ids)
            await client.post(f"/accounts/{acc}/deposit", json={"amount_cents": 100})
        elif kind == "withdraw":
            acc = random.choice(account_ids)
            await client.post(f"/accounts/{acc}/withdraw", json={"amount_cents": 100})
        elif kind == "transfer":
            src, dst = random.sample(account_ids, 2)
            await client.post(
                "/transfer",
                json={
                    "from_account_id": src,
                    "to_account_id": dst,
                    "amount_cents": 100,
                },
            )
        else:
            acc = random.choice(account_ids)
            await client.get(f"/accounts/{acc}")
    except httpx.HTTPError:
        pass
    return time.monotonic() - start


async def run_at_rate(
    client: httpx.AsyncClient, account_ids: list[str], rps: int, duration_s: int
) -> list[float]:
    latencies = []
    interval = 1.0 / rps
    end_at = time.monotonic() + duration_s
    tasks = []
    while time.monotonic() < end_at:
        tasks.append(asyncio.create_task(one_request(client, account_ids)))
        await asyncio.sleep(interval)
    for t in tasks:
        latencies.append(await t)
    return latencies


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--accounts", type=int, default=20)
    parser.add_argument("--start-rps", type=int, default=2)
    parser.add_argument("--max-rps", type=int, default=200)
    parser.add_argument("--step-rps", type=int, default=10)
    parser.add_argument("--step-seconds", type=int, default=10)
    args = parser.parse_args()

    async with httpx.AsyncClient(base_url=args.base_url, timeout=10.0) as client:
        print(f"==> seeding {args.accounts} accounts", file=sys.stderr)
        account_ids = await seed_accounts(client, args.accounts)

        rps = args.start_rps
        while rps <= args.max_rps:
            print(f"==> ramping to {rps} req/s for {args.step_seconds}s", file=sys.stderr)
            latencies = await run_at_rate(client, account_ids, rps, args.step_seconds)
            if latencies:
                latencies.sort()
                p50 = latencies[len(latencies) // 2]
                p99 = latencies[int(len(latencies) * 0.99)]
                print(
                    f"    {len(latencies)} requests, p50={p50*1000:.0f}ms "
                    f"p99={p99*1000:.0f}ms",
                    file=sys.stderr,
                )
            rps += args.step_rps


if __name__ == "__main__":
    asyncio.run(main())
