# Status

Read this first when resuming work cold.

## M3's backup/restore half of DR: DONE (the failover half is a real open decision, not solved)

`apps/ledger-service/backup.sh` / `restore.sh`: `pg_dump --clean
--if-exists` / `psql` round-trip. Tested for real — not through
`docker compose` (blocked here, see the entry below), directly against
Postgres: dumped a database with real data (11 accounts, 201
transactions accumulated from this session's own testing), dropped
every table (simulating the node dying outright), restored from the
dump, confirmed every balance came back byte-for-byte. CI runs the
same round-trip through the actual `docker compose exec` wrapper these
scripts use, where Docker Hub is reachable.
`docs/runbooks/ledger-backup-restore.md` documents it.

**What this deliberately does not solve**: each `banking_app_nodes`
host runs its own independent Postgres right now — there's no shared
state, no replication, no automatic failover. Backup/restore answers
"how do I recover a dead node's data," not "what happens to in-flight
traffic when a node dies right now." Real replication (which node is
primary, how a client fails over, split-brain avoidance) is a genuine
architecture decision — flagged in the runbook rather than silently
built alone, since it changes what "a node" even means for this
workload and isn't something to decide unilaterally while the lab's
owner is away.

## M3 (started early) — ledger-service: DONE, and actually execution-verified this time

Unlike the M1/M4 entries below (statically verified only, because this
authoring environment's Python/apt integration is broken), this one
got real execution testing: FastAPI + Postgres, run for real — a real
`postgresql` install, a real `uvicorn` process, real `curl` requests —
not just written and hoped over. What that caught:

- **A real concurrency bug, before it shipped**: the first `deposit`
  endpoint did `account.balance_cents += amount` — a Python read-
  modify-write, which loses updates under concurrent deposits to the
  same account (`withdraw`/`transfer` were already written as atomic
  SQL-side conditional updates, for the insufficient-funds check;
  `deposit` just hadn't been held to the same standard yet). Caught by
  inspection before running anything, then proved with the fix in
  place: 50 concurrent deposits of 100 cents each land on exactly 5000,
  every time — `apps/ledger-service/smoke-e2e.sh` codifies this check
  permanently, it's not a one-off manual test.
- Every endpoint verified against a real running instance: account
  creation, deposit, withdraw, insufficient-funds rejection (400),
  transfer (both sides' balances), transaction history, 404 on an
  unknown account, and `/metrics` actually exposing Prometheus series.
- `apps/ledger-service/load-generator.py` (ramps request rate,
  deliberately built to *create* the bottleneck the lab exists to show)
  run for real against the live instance and produces sane per-step
  p50/p99 latencies.
- `docker compose config` validates the compose file's schema.
  **Not verified here**: the actual `docker build`/image pull — this
  sandbox's egress proxy rejects Docker Hub's CDN (CloudFront presigned
  URLs don't tolerate the TLS-intercepting proxy; confirmed via
  `$HTTPS_PROXY/__agentproxy/status` — `production.cloudfront.docker.com`
  shows a hard `connect_rejected`, not a fixable config gap on this
  end). The real machines pull over their own home-network connection,
  not through this sandbox, so this specific gap shouldn't reproduce
  there — but it's the one thing this entry can't claim to have proven.
- `banking-app` Ansible role (Docker + compose plugin from Debian's own
  archive — no external repo needed, unlike Grafana) is statically
  verified (ansible-lint production profile, including real module-
  resolution against the newly-added `community.docker` collection)
  but not execution-tested, same limitation as M1/M4.

Deployed to `banking_app_nodes` (Pi + MorePower, deliberately not the
Freebox VM — see `monitoring_host`'s comment in `hosts.yml` for why
keeping monitoring on its own dedicated host matters for a fair
load-test comparison).

## M4 (started early) — monitoring stack: Prometheus + Grafana: DONE (statically verified)

Brought forward from the roadmap's original M4 slot because it's the
most direct way to make the lab's actual point visible: three
completely different machines (Pi 4B, a Freebox-hosted VM, a VMware
Workstation VM), each with different CPU/RAM/disk, side by side on one
dashboard — the foundation for a real ramp-up/down story later (M3+),
not just a nice-to-have.

- `node-exporter` role (applied to `hosts: all`): installs
  `prometheus-node-exporter` (real Debian package) plus `avahi-daemon`
  so every machine advertises itself as `<hostname>.local` — no manual
  IP bookkeeping.
- `monitoring-stack` role (applied to inventory's new `monitoring_host`
  group — the Freebox VM, chosen for being always-on independent of
  anyone's laptop): Prometheus (Debian package) scraping every real
  machine by mDNS name; Grafana (Debian doesn't package it, so its own
  apt repo + signing key are added) with the Prometheus datasource and
  a first dashboard (CPU%, memory%, disk free, load average, faceted by
  instance) both provisioned automatically — opening Grafana for the
  first time needs zero manual click-through.
- `monitoring_host` is a separate inventory axis from `freebox_nodes`
  on purpose: what a machine's hardware *is* and what it *runs* aren't
  the same thing, and moving the monitoring stack to a different
  machine later should be a one-line inventory change.

**Verification honesty note, same as M1's**: ansible-lint (production
profile), playbook syntax-check, yamllint, and the dashboard/datasource
JSON/YAML are all validated; all four apt package names (`prometheus`,
`prometheus-node-exporter`, `avahi-daemon`, `libnss-mdns`) confirmed to
actually exist in a Debian-family archive. Actual execution — Grafana
reachable, dashboard populated, mDNS resolution working between real
machines on the real LAN — is the next real machines' reconcile pass
to prove, same as M1.

## Pull-loop bug, round two: a second broken fix landed, now actually fixed

Between the first fix below and this entry, five commits landed on
`main` outside this session (`586ae72`..`1fe8617`) — someone iterating
directly against the real machines, most likely without seeing the
first fix yet. Net result, the good and the bad:

**Real problem they found that the first fix missed**: `-i localhost,`
(what the first fix used) creates an ad hoc inventory containing a
single host literally named `"localhost"`. `--limit "%H"` against that
matches **zero hosts** — the reconcile run "succeeds" (exit 0) having
done nothing at all. Silent no-op dressed as success is exactly the
failure shape this repo keeps having to learn the hard way. Their
fix — point `-i` at the real `infra/ansible/inventory/hosts.yml`, keyed
by each machine's actual hostname — is correct and is kept.

**What they broke on the way**: `--limit "${HOSTNAME}"` to fill in the
current host's own name. Same root cause as the very first bug:
`ExecStart=` isn't run through a shell, so this isn't bash's `$HOSTNAME`
special variable — it's systemd's own environment-variable expansion,
and nothing sets an actual `HOSTNAME` env var for this service. Verified
directly: `env -i /bin/sh -c 'echo [${HOSTNAME}]'` prints `[]`. So this
was *also* silently matching nothing — meaning the "MorePower" enrollment
report claiming a flawless first run (`failed=0, changed=0`) almost
certainly describes a run that touched zero hosts, not a verified
baseline. Re-run it after this fix and expect `changed>0` the first
time (unattended-upgrades gets installed, etc.) — `changed=0` on a
*first* run is the same red flag `changed=0` was the reassuring sign for
a *repeat* run.

Fixed by going back to `%H` (systemd's own hostname specifier — no
shell, no environment variable, no escaping trap for the next person to
fall into) combined with the corrected `-i` from the second round.
`ARCHITECTURE.md`'s "enroll now, assign a group later" paragraph is
also updated: it doesn't survive contact with a name-scoped `--limit`
(an unlisted host matches nothing, not a documented `ungrouped`
fallback), so the doc now describes what's actually running — one
commit adds a host directly to its group — instead of a design that
didn't make it past the first three real machines.

**Open item, not yet verified**: the Freebox VM's inventory key is
`smallrevolt` — confirmed as its Linux *username*, but never confirmed
as its actual `hostname`. If those differ, `--limit "%H"` silently
matches zero hosts on that machine too, the same way as the last two
bugs. Run `hostname` on it and confirm it prints `smallrevolt` exactly
(case-sensitive) before trusting its reconcile logs.

## First real machine enrolled: found and fixed a pull-loop bug: DONE

`ITSaRevolution` (Raspberry Pi 4B, Raspberry Pi OS Lite 64-bit) was the
first machine ever actually enrolled — and it immediately proved the
static verification note in the M1 entry below right: `enroll.sh`'s
generated `homelab-reconcile.service` failed every run with
`ansible-playbook: error: argument -l/--limit: expected one argument`.

Root cause: `ExecStart=` in a systemd unit is **not** run through a
shell. `--limit "$(hostname)"` in the unit file is not a command
substitution there — systemd parses `$(...)` as its own (invalid)
environment-variable syntax, silently expands it to nothing, and the
`--limit` flag ends up with no argument at all. This is exactly the
"looked right, only fails on the thing that actually executes it"
class of bug the Windows os-error-5 postmortem (see the ITSaNAS
repo's STATUS.md) is named for — caught here on the very first real
run instead of after the fact, because the enroll runbook explicitly
says to watch `journalctl` on first boot.

Fixed by using systemd's own hostname specifier (`%H`), which systemd
expands itself with no shell involved — removes the bug class
entirely rather than patching around it (e.g. wrapping in `bash -c`
would have worked but adds a process and reintroduces the same
escaping trap for the next person who edits that line).
`ARCHITECTURE.md`'s prose showed the same broken snippet; fixed there
too with an explanation, so a reader doesn't copy the mistake.

## M2 (partial) — Terraform skeleton + network design: IN PROGRESS

`infra/terraform/` now has the real resource shapes (VMs cloud-init
straight into the M1 pull loop; counts default to zero so `plan` is a
no-op until M2 starts for real), `docs/network.md` documents the
segmented VLAN topology and its firewall rules, and CI runs
`terraform fmt`+`init`+`validate` on every push (the authoring
environment can't reach the Terraform registry, so provider-schema
validation deliberately lives in CI — fmt and HCL parseability are
checked before push). Proxmox remains an explicitly flagged assumption.

## M1 — base-hardening role fleshed out: DONE (statically verified)

`base-hardening` now does real work: unconditional unattended security
updates, plus toggle-gated SSH lockdown (key-only, no root, sshd -t
validated, reload handler) and UFW default-deny — lockout-shaped
changes default OFF and are enabled per group in the inventory, because
this role runs unattended on real machines via the pull loop (see
defaults/main.yml for the reasoning). Collections the playbook needs
are declared in `infra/ansible/requirements.yml`, installed by
enroll.sh at enrollment and refreshed before every reconcile run, and
installed in CI before ansible-lint.

**Verification honesty note**: ansible-lint (production profile),
playbook syntax-check, and yamllint all pass; ansible-lint is now a
blocking CI step. Actual *execution* of the role could not be verified
in the authoring environment (its system Python's cryptography module
is broken in a way that kills every apt-module run — environmental,
not a playbook defect). The first really-enrolled machine is the
execution test; the enroll runbook instructs watching the first
reconcile pass for exactly this reason. Runbooks added:
`docs/runbooks/enroll-a-machine.md`, `decommission-a-machine.md`.

## M0 — repo scaffold & governance: DONE

Scaffolding this repo: README, LICENSE (Unlicense), ROADMAP.md,
ARCHITECTURE.md (the GitHub-as-nerve-center pull design), this file,
directory layout, and a CI skeleton. No infra exists yet — nothing in
this repo has been applied to a real machine.

Confirmed with the owner: this repo is deliberately public and
unprotected (no branch protection, no required reviews) — it's a
disposable interview-prep lab, not a system meant to outlive the
interview it's built for.

Open questions that would sharpen M1+ (currently working from the
assumptions written into `ROADMAP.md`'s intro — update this section
once these are answered):
- Actual hypervisor/hardware in the lab (assumed: Proxmox VE).
- Which specific role/interview this is aimed at, if that should shape
  which parts of "banking ops" get the most depth (HA/DR? security
  compliance posture? observability? straight platform engineering?).

## Next steps

1. M1 — the pull loop itself: `bootstrap/enroll.sh`, the systemd timer,
   `infra/ansible/site.yml`, inventory conventions, first
   `base-hardening` role. This is the milestone that makes the repo
   actually do something to a machine — see `ROADMAP.md`.
