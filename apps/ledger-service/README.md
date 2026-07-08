# ledger-service

A small FastAPI + Postgres banking ledger (accounts, deposit/withdraw/
transfer, transaction history) — the M3 workload deployed to
`banking_app_nodes` (the Pi and MorePower) via `docker compose`, see
`infra/ansible/roles/banking-app`.

| Script | What it's for |
|---|---|
| `smoke-e2e.sh` | Every endpoint, plus the concurrency check (50 simultaneous deposits land on the exact right balance) — the permanent regression test, run in CI on every push |
| `load-generator.py` | Ramps request rate against one running instance — the tool that *creates* a bottleneck rather than describing one |
| `run-demo.sh` | **The actual demo**: runs `load-generator.py` against both real `banking_app_nodes` (Pi + MorePower) at once, side by side, while Grafana (`http://smallrevolt.local:3000`) shows the weaker node visibly saturate first |
| `backup.sh` / `restore.sh` | `docs/runbooks/ledger-backup-restore.md`'s actual mechanism — the tested answer to "what happens when a node dies" (the data half; see that runbook's "known gap" for the half that isn't solved yet) |

## Local development

```sh
docker compose up --build
BASE_URL=http://127.0.0.1:8000 ./smoke-e2e.sh
```
