#!/usr/bin/env bash
# Backs up the ledger's Postgres data to a timestamped, plain-SQL dump.
# This is the actual DR answer for "what happens when a banking_app_
# nodes host dies" right now: each node runs its own independent
# Postgres (see docker-compose.yml — no cross-node replication exists
# yet, that's real future architecture work, not something to fake).
# A cron/systemd timer running this regularly, with the dump copied
# somewhere off that specific machine, is what makes "the node died"
# survivable instead of a real data-loss event.
#
# Usage: ./backup.sh [output-directory, default: ./backups]

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

OUT_DIR="${1:-./backups}"
mkdir -p "$OUT_DIR"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_FILE="${OUT_DIR}/ledger-${TIMESTAMP}.sql"

echo "==> dumping the ledger database to ${OUT_FILE}"
docker compose exec -T db pg_dump -U ledger --clean --if-exists ledger >"${OUT_FILE}"

echo "==> backup written: ${OUT_FILE} ($(du -h "${OUT_FILE}" | cut -f1))"
