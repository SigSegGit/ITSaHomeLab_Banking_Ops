#!/usr/bin/env bash
# Restores a dump produced by backup.sh into a running ledger stack's
# Postgres. `--clean --if-exists` in the dump means this is safe to run
# against a database that already has (stale, or empty) tables — they
# get dropped and recreated from the dump, not merged with what's there.
#
# Usage: ./restore.sh path/to/ledger-TIMESTAMP.sql

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

DUMP_FILE="${1:?usage: ./restore.sh path/to/ledger-TIMESTAMP.sql}"
if [ ! -f "$DUMP_FILE" ]; then
    echo "no such file: $DUMP_FILE" >&2
    exit 1
fi

echo "==> restoring ${DUMP_FILE} into the running ledger database"
docker compose exec -T db psql -U ledger -d ledger <"${DUMP_FILE}"

echo "==> restore complete"
