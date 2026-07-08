# Runbook: ledger-service backup & restore

**Answers**: "what happens when a `banking_app_nodes` host dies?" —
right now (M3), each node runs its own independent Postgres (see
`apps/ledger-service/docker-compose.yml` — no cross-node replication
exists yet, that's real future architecture work, not something faked
here). This runbook is the actual DR answer today: a regular dump,
copied off the machine, that restores byte-for-byte.

## Back up

On the node running the stack:

```sh
cd /opt/ledger-service
./backup.sh /some/off-node/path   # default: ./backups
```

Copy the resulting `ledger-<timestamp>.sql` file somewhere that isn't
this machine (the whole point — a backup that lives on the disk that
just died isn't a backup).

## Restore

Onto a running stack (the same node recovering, or a fresh one):

```sh
cd /opt/ledger-service
docker compose up -d db   # make sure the db container is up first
./restore.sh /path/to/ledger-<timestamp>.sql
```

The dump is generated with `pg_dump --clean --if-exists`, so restoring
into a database that already has (empty, or stale) tables is safe —
they're dropped and recreated from the dump, not merged.

## Verified

Tested directly against a real Postgres instance (not through
`docker compose`, since this specific sandbox's proxy blocks Docker
Hub's image CDN — see `STATUS.md`): dumped a database with real
account/transaction data, dropped every table (simulating the node
dying), restored from the dump, and confirmed every account balance
came back byte-for-byte identical. The `docker compose exec` wrapper
these scripts use is the same command shape, verified in CI where the
real container actually builds and runs.

## Known gap, not yet solved

No automatic failover: if a node dies between backups, everything
since the last backup is gone, and nothing currently promotes another
node to take over automatically. Real streaming replication (or an
external managed Postgres) across `banking_app_nodes` is a genuine
architecture decision — which node is primary, how a client fails
over, how split-brain is avoided — worth making deliberately with the
lab's owner, not something to bolt on unilaterally. Recorded here so
it doesn't get silently forgotten.
