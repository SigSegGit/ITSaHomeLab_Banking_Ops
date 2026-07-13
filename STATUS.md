# Status

Read this first when resuming work cold. Read `CLAUDE.md`'s "THE
MISSION" section *before* this file — this repo's actual purpose
(Patroni HA PostgreSQL demo for a Revolut DBRE interview) took several
hours and a lot of owner frustration to correctly establish tonight;
don't let this file's older, pre-correction entries below drift you
back toward the wrong framing ("generic homelab weekend resilience").

## THE DEMO WORKS, END TO END, FOR REAL (2026-07-13)

Confirmed live, in this order, right before the interview: real
2-node Patroni cluster (`smallrevolt` + `MorePower`, Postgres 16,
streaming replication, 0 lag) → `ledger-service` connected via
multi-host DSN → a real account created and deposited into via the
actual HTTP API → a continuous 80-request write load run against it
→ a live `patronictl switchover` (smallrevolt → morepower → back to
smallrevolt) → **80/80 requests succeeded, zero failures**, confirmed
in Prometheus (`patroni_primary` flipped instantly) and Grafana (all
8 dashboard panels backed by real, verified metric names — nothing
guessed). No GCP, no witness workaround needed for this: a *planned*
switchover is quorum-safe with 2 raft members since nothing goes down
mid-operation — see the "3rd raft vote" reasoning below for why an
unplanned crash is a different story.

Getting here from "topology decided" to "actually working" surfaced
**9 real, reproduced-live bugs**, each fixed for real and verified
again after, not just patched-and-hoped:
1. `base-hardening`'s keyboard-layout task crashed the whole reconcile
   on headless VMs (`/etc/default/keyboard` doesn't exist without
   console-setup).
2. `apt_repository` needs the `gpg` binary — missing on MorePower's
   minimal Debian trixie image.
3. Patroni 4.x silently dropped `bootstrap.users` entirely — the
   `admin` role never got created despite bootstrap reporting success,
   no error, no warning outside one easy-to-miss log line.
4. `community.postgresql.postgresql_membership` wants `groups`/
   `target_roles` (lists), not `group`/`target` (singular) — wrong
   parameter names, not a permissions issue.
5. Docker's embedded DNS on the default bridge network does not
   inherit the host's Tailscale MagicDNS — fixed by pointing the
   container at Tailscale's own resolver (100.100.100.100) directly.
6. `banking-app`'s `.env` deploy task was gated on `patroni_db_nodes`
   group membership instead of running unconditionally (the whole role
   is already scoped to `banking_app_nodes`) — silently correct only
   by coincidence.
7. Docker's bridge-network IP isn't covered by `pg_hba.conf` by
   default — needed an explicit `172.16.0.0/12` entry.
8. **The big one**: `bootstrap.pg_hba` (and even
   `bootstrap.dcs.postgresql.pg_hba`) is a *one-time-only* setting —
   Patroni applies it once, at initial cluster creation, and never
   again. Editing it and redeploying has *zero effect* on an
   already-running cluster, no error. The actually-supported mechanism
   for live changes is Patroni's dynamic config (`PATCH .../config` or
   `patronictl edit-config`) — used live to unblock the demo, and now
   documented in the template so the lesson isn't lost.
9. Postgres 15+ no longer grants `CREATE` on the `public` schema to
   every role by default, only the schema/database owner — `ledger`
   was owned by `postgres`, not `admin`; ledger-service crash-looped
   on its very first `CREATE TABLE` until the database's owner was
   fixed to match who actually uses it.
10. `dhcpcd` (MorePower's network manager) rewrites `/etc/resolv.conf`
    on every DHCP renewal, silently dropping tailscaled's injected
    resolver — DNS worked right after `tailscale set --accept-dns=true`
    and then broke again later with no config change, mid-switchover-
    test. Fixed via dhcpcd's own `resolv.conf.head` override, which
    survives renewals.

Every one of these was found by actually running the thing against
real machines, not by reading code more carefully — which is the
whole point of this repo's "verify before pushing" rule, and a live
demonstration of exactly the kind of troubleshooting the job
description asks for ("comfortable troubleshooting live production
issues... replication configuration... PostgreSQL internals").

## Topology pivot (2026-07-13): itsarevolution unreachable, gcp-burst-1 reactivated as the 3rd raft vote

Interview is today. `itsarevolution` never came back (see the entry
below) and the owner asked explicitly: the demo must still work
without it, including live automatic failover — not just monitoring.
Quorum math forces the shape of the fix: raft needs a strict majority,
so 2 voting members can't survive losing either one (1-of-2 isn't a
majority), which is exactly the automatic-failover demo. Colocating a
2nd raft process on one of the 2 remaining physical machines was
considered and rejected — if that *same* machine is the one killed,
its DB-node vote and its colocated witness vote both disappear
together, breaking quorum in exactly the direction the demo needs to
work. A 3rd voter has to be genuinely independent.

**New shape**: `smallrevolt` promoted from witness-only to a real
Postgres+Patroni DB node, alongside `MorePower`. `gcp-burst-1`
(`infra/terraform-gcp`, built 2026-07-11/12, never applied) takes the
witness slot instead — genuinely independent (own public IP, not on
the home network/power at all), which is a real advantage for the 3rd
vote specifically, not just a fallback of convenience.
`hosts.yml`/`group_vars/patroni_db_nodes/vars.yml`/
`host_vars/gcp-burst-1.yml` all updated to match. Revert path if
itsarevolution comes back later: swap it back in for `smallrevolt` in
`patroni_db_nodes`, put `gcp-burst-1` back to witness-standby — see
git history for the exact prior shape (commit before this entry).

**Not yet done**: this is config-only so far. Actually applying it
needs `terraform apply` in `infra/terraform-gcp/` (owner's GCP project
ID + billing account ID — neither `terraform` nor `gcloud` are
installed in this session's environment), then enrolling the new VM
the same way as every other host, then Tailscale-joining it (same
manual login-URL flow as the other two, see above), then running the
`patroni-postgres` role on `MorePower`+`smallrevolt` and
`patroni-raft-witness` on `gcp-burst-1`.

## Dashboard: node status panel added, works regardless of pool membership

`infra/ansible/roles/monitoring-stack/files/dashboard-lab-overview.json`
gained a "Node status" row (`up{job="node"}` per instance, red/down —
green/up, color-coded) across the full dashboard width — the owner
asked for a real per-machine status report that doesn't depend on
which nodes actually end up reachable at demo time. This is genuinely
resilient to the `itsarevolution` situation: Prometheus scrapes it by
name regardless (`monitoring_scrape_targets` in
`roles/monitoring-stack/defaults/main.yml` already lists all 3), so if
it's down, the dashboard visibly, honestly says so instead of just
having a gap. Not yet deployed to the real `smallrevolt` Grafana
instance — next reconcile pass picks it up via the existing dashboard
provisioning (`grafana-dashboard-provider.yml`), no manual step needed.

## Tailscale: 2 of 3 nodes really enrolled (2026-07-13), no auth key exists

`smallrevolt` and `MorePower` are confirmed joined to the real tailnet
(`tail943111.ts.net` — filled into `group_vars/patroni_cluster/vars.yml`
from the owner's admin console screenshot), verified with a real
`tailscale status` on both showing each other as peers. `itsarevolution`
is still not joined — it's unreachable entirely (see below).

**How this actually got done, since no reusable auth key was ever
generated**: this session SSH'd into each host directly (bypassing the
unattended pull-loop for this one bootstrap step, since a login URL
needs a human to click it) and ran `tailscale up` with no `--authkey`,
which prints a `https://login.tailscale.com/a/...` URL; the owner
approved each one from his phone (once via a plain link, once via a
QR code rendered for the same URL). `infra/ansible/roles/tailscale/`
is updated to match this reality: `tailscale_auth_key` is no longer a
hard-required assert, and the role now fails loudly (naming the exact
manual command) rather than silently no-op'ing when a node isn't
logged in and no auth key exists — it does NOT attempt the login flow
itself, since an unattended reconcile run has no human watching to
click the URL.

**`MorePower` had no deployed SSH key at all** (unlike the other two,
there's no `host_vars/MorePower.yml`, so `base-hardening` never ran
there) — the owner gave its real login (`morepower` / real password,
not written here or anywhere in the repo) for a one-time password
auth, used only to deploy the same lab SSH key that's on the other two
hosts, immediately confirmed working, password never reused after
that. `host_vars/MorePower.yml` doesn't exist yet — creating it (with
this same authorized_key + firewall port prep, matching the other two
hosts' host_vars) is a real remaining gap before `base-hardening` can
manage this host the normal way.

**Real bug caught doing this, worth remembering**: chaining
`some-download | (echo password | sudo -S tee file)` silently produces
an empty file — the inner pipe's `echo` steals stdin from `tee`, so
the downloaded content never reaches it, and the whole thing exits 0
with no error. Correct pattern: download to a temp file as the
unprivileged user first, then `sudo mv` it into place. Same class of
"looks right, silently does nothing" bug this repo's STATUS.md has
hit before (the `%H`/`--limit` saga above).

## Topology correction (2026-07-12): all 3 real machines confirmed alive, demo targets them instead of the GCP node

Owner correction, in chat, overriding the GCP-standin plan below and in
`ROADMAP.md`/`CLAUDE.md`'s prior framing: `ITSaRevolution` (Pi),
`smallrevolt` (Freebox VM), and `MorePower` (laptop VM) are **all
working right now**. The demo's Patroni cluster now targets
`MorePower` + `ITSaRevolution` as the 2 Postgres nodes, `smallrevolt`
as the raft witness — the original 3-machine, weakest-vs-strongest
topology `ROADMAP.md`'s M3 section describes, not the GCP-burst
stand-in built for it below. `infra/terraform-gcp` and `gcp-burst-1`
stay in the repo (real, ready, CI-validated) but are out of the active
inventory groups — see `hosts.yml`, `group_vars/patroni_db_nodes/vars.yml`,
`host_vars/ITSaRevolution.yml`, `CLAUDE.md`, all updated to match.

This does **not** retroactively invalidate the dmesg-confirmed ext4
block-bitmap corruption documented in the entry directly below — that
was a real hardware-level finding, not a misread. It means the machine
is reachable and being put back to work despite it. Worth a quick
`dmesg | grep -i ext4` sanity check before loading it with Patroni +
Docker for real, rather than assuming the earlier finding has
resolved itself.

## ITSaRevolution's dpkg lockup: real root cause found, fixed for real — SD card health still unconfirmed

The owner diagnosed the actual mechanism behind the repeated dpkg
corruption chased earlier tonight: `python3`'s postinst runs
`py3clean` via a generic hook system
(`/usr/share/python3/runtime.d/*.rtupdate`), and one specific hook —
`linux-kbuild-6.18.34+rpt.rtupdate` — calls `dpkg -L` on that package
to enumerate its files. That package's own metadata in
`/var/lib/dpkg/info/` was corrupted/missing, so the hook threw an
unhandled Python exception and took the entire `dpkg --configure -a`
run down with it (`python3` itself failing to configure, exit status
4) — not a problem with the package actually being installed, a
crash in an unrelated package's cleanup hook.

**Fix**: `sudo mv /usr/share/python3/runtime.d/linux-kbuild-6.18.34+rpt.rtupdate /tmp/`
(isolate, don't delete) then `sudo dpkg --configure -a`. Confirmed:
`apt-get install -f` now reports a clean state, and
`homelab-reconcile.service` completed a full run with `failed=0` —
also incidentally confirms the vault-password-provider design from
the Patroni work above works correctly for a non-`patroni_cluster`
host (no real vault password ever placed on this machine, and nothing
broke).

**Still true, not superseded by this fix**: the `dmesg`-confirmed
`EXT4-fs error ... bad block bitmap checksum` on block groups
240/368/464 (see the entry further below) is a *different* bug from
the same suspect hardware — real kernel-level filesystem corruption,
not a dpkg-hook crash. This fix resolves one specific symptom; it does
not confirm the SD card itself is healthy. `ITSaRevolution` stays out
of `banking_app_nodes`/`patroni_db_nodes` per CLAUDE.md's mission
section until someone actually checks the card (read-only `e2fsck -n`
or a fresh card) — a clean `dpkg --configure -a` on its own isn't that
confirmation, however good the diagnostic work behind it was.

## Patroni HA PostgreSQL cluster: built and statically verified, NOT yet deployed to real machines

Real deliverable for the mission (see CLAUDE.md). Built tonight,
nothing applied to real hardware yet — that's the explicit next step,
blocked on two things only the owner can provide (below).

**What exists**: `infra/ansible/roles/tailscale/` (stable NAT-traversing
addressing — needed because `MorePower` roams and can't otherwise be a
reachable Patroni/raft peer), `infra/ansible/roles/patroni-postgres/`
(PostgreSQL 16 via PGDG + Patroni via pip venv, drops Debian's
auto-created default cluster since Patroni owns the data dir),
`infra/ansible/roles/patroni-raft-witness/` (a Postgres-less
`patroni_raft_controller` on `smallrevolt`, purely for raft quorum —
2 Postgres nodes alone can't lose either one without losing majority,
which would break automatic failover exactly when it needs to prove
itself). `apps/ledger-service` now connects via a multi-host libpq DSN
(`host=nodeA,nodeB&target_session_attrs=read-write`) instead of a
standalone `db` container — psycopg2/libpq itself finds whichever node
is currently primary, no HAProxy/pgbouncer needed for that part.
Credentials are `ansible-vault`-encrypted in
`group_vars/patroni_cluster/vault.yml` (3 real, randomly-generated
passwords; the Tailscale auth key is still a placeholder — see below).
`bootstrap/enroll.sh` now deploys a vault-password-provider script on
every machine so `--vault-password-file` never breaks a host that
doesn't actually need it (confirmed: `ansible-playbook --syntax-check`
and `ansible-lint` both pass with zero vault password available at
all, matching CI's exact invocation).

**Verified for real, not just linted**: rendered `patroni.yml` against
Patroni's own `--validate-config` (installed in a scratch venv) —
schema-valid; the only remaining complaint against a real hostname was
"is not reachable" on the raft port, which is *expected* with no real
node listening yet, not a template bug. Rendered the ledger-service
`.env`'s DSN and built a real SQLAlchemy engine from it successfully.
`docker compose config` accepts the new compose file. Full
yamllint/ansible-lint/syntax-check suite passes, matching CI exactly.

**Explicitly not done**: no `patronictl list` has ever run for real, no
failover has been demonstrated, no replica ramp-up/down via
Terraform+Ansible has happened, no Grafana dashboard for Patroni/
Postgres metrics exists yet (no `postgres_exporter` role either).

**Two hard blockers, owner-only**:
1. `tailscale_tailnet_domain` (`group_vars/patroni_cluster/vars.yml`)
   is deliberately an empty string — needs the owner's real Tailscale
   tailnet MagicDNS suffix. The `tailscale` role asserts and refuses to
   run rather than guess wrong and silently misconfigure every node's
   address.
2. `tailscale_auth_key` in the vault is still a placeholder string —
   needs a real key from the Tailscale admin console.

Also still open: `infra/terraform-gcp/` is real and ready but has never
been `terraform apply`'d (needs the owner's GCP project ID + billing
account ID, see that directory's README.md).

## Correction: this repo's actual mission was mis-framed for hours tonight

Earlier tonight, this session (and the entries immediately below this
one) treated the repo as a generic "make the homelab resilient for the
weekend" exercise — chasing SD card corruption, SSH tunnels, and GCP as
a vague nice-to-have. The owner had to forcefully correct this multiple
times, increasingly frustrated, before the real mission (Patroni HA
PostgreSQL demo for a Database Reliability Engineer interview at
Revolut, Monday) was actually established. `CLAUDE.md` now has this
locked in a "THE MISSION" section at the top specifically so it
survives context compaction and isn't rediscovered the hard way again.
The entries below are kept for their genuine real-hardware findings
(the SD card corruption on `ITSaRevolution` is real and still relevant
— it's why that machine isn't in the Patroni cluster), but their
framing of *why* any of this matters should be read through the lens
of the mission section above, not taken at face value.

## First real reconcile on all 3 machines: 2 real bugs found, fixed; 1 needs owner action

The owner ran a reconcile on all three real machines for the first
time. `smallrevolt` (M4 monitoring) genuinely works — Prometheus and
Grafana confirmed `active (running)`, healthy, on real hardware, for
real. Two real bugs surfaced on the other two:

1. **`banking-app` failed on `MorePower`**: `No package matching
   'docker-compose-v2' is available`. This package name was verified
   against Ubuntu's archive (this sandbox), never against Debian 13
   (Trixie, `MorePower`'s actual OS) — a real verification gap.
   Bundling `docker.io` + `docker-compose-v2` + `rsync` in one
   `ansible.builtin.package` task also meant the one failure blocked
   Docker itself from installing at all (`docker: command not found`).
   Fixed: split into separate tasks, added `update_cache: true` (the
   most likely actual cause — a freshly-imaged machine's apt cache
   can be stale until something forces a refresh), and added a
   fallback that downloads the official `docker/compose` v2 plugin
   binary directly if the distro package genuinely isn't resolvable.
   **Honesty note**: this session's own environment blocks GitHub
   release downloads outside its authorized repo scope (a deliberate
   proxy restriction, confirmed via the exact same
   `github access to this repository is not enabled` message the
   `add_repo` tool would show), so the fallback binary URL could not
   be verified from here. The primary fix (`update_cache: true` on the
   real distro package) is standard, well-understood Ansible/apt
   behavior and didn't need external verification.

2. **`ITSaRevolution` (the Pi) reconcile fails entirely**:
   `fatal: bad config line 1 in file /etc/gitconfig`, blocking every
   `git pull` run as root (including the systemd service's own
   `ExecStartPre`). Root cause suspected: a hand-run
   `git config --system --add safe.directory ...` (correct instinct,
   likely malformed syntax) corrupted the system-wide gitconfig at
   some point outside this repo's own tooling — `enroll.sh` never set
   this itself. **This needs the owner's hands on the actual machine**
   (this session has no access to it) — fixed here only by adding a
   correct, idempotent `git config --system safe.directory
   "${INSTALL_DIR}"` to `enroll.sh` itself, so re-running enrollment
   (after the owner clears the corrupted file) sets it properly and
   this class of problem doesn't recur, including for the GCP node
   that still needs enrolling.

3. **Grafana dashboard "Failed to fetch" on `smallrevolt`**: the
   Prometheus datasource provisioning never set an explicit `uid`, so
   Grafana auto-generated a random one that doesn't match the literal
   `"Prometheus"` UID the dashboard JSON's panels reference. Fixed:
   explicit `uid: Prometheus` in the datasource provisioning file —
   Grafana's provisioning reconciles by `name` on reload, so the next
   reconcile + grafana-server restart should repoint the existing
   datasource to the correct UID without needing a fresh install.

## Weekend-away resilience push (owner unreachable until after interview): IN PROGRESS

Owner is leaving home for the weekend; the real demo (this whole repo
exists for a job interview Monday) needs to work reliably without them
physically present. Correction to an earlier assumption in this file:
`MorePower` (the owner's laptop VM) does **not** go fully offline when
they leave — the laptop travels with them and keeps running, it just
loses LAN connectivity to home (no more `*.local` mDNS, no direct
reach to smallrevolt/ITSaRevolution's HTTP ports). See "Reaching
everything while away" below for how that's actually handled.

### Quick reference: reaching everything while away

Home's external address: `ngas.fr` (DDNS, points at the router). Only
SSH is port-forwarded from the router — 22101→ITSaRevolution:22,
22102→smallrevolt:22. Nothing else (Grafana/Prometheus/ledger-service
ports) is forwarded, so reaching them from outside the LAN means
tunneling over the SSH that already works:

```bash
# Grafana + Prometheus (both live on smallrevolt) — run from anywhere,
# including MorePower once it's off the home LAN
ssh -p 22102 -L 3000:localhost:3000 -L 9090:localhost:9090 -N smallrevolt@ngas.fr
# then browse http://localhost:3000 locally

# ITSaRevolution (Pi) — SSH only right now, see below for why
ssh -p 22101 -N itsarevolution@ngas.fr
```

### ITSaRevolution (Pi): confirmed failing SD card, pulled from banking_app_nodes

First real reconcile attempts on the Pi surfaced repeated, unrelated
file corruption: `/etc/gitconfig`, then `/root/.gitconfig`, then two
different `dpkg` package-list files (`gir1.2-girepository-2.0:arm64`,
`python3-dbus`). Patching each one let the reconcile progress further
each time, until `dmesg` showed the actual root cause for real:

```
EXT4-fs error (device mmcblk0p2): ext4_validate_block_bitmap:423: bg 240/368/464: bad block bitmap checksum
EXT4-fs (mmcblk0p2): error count since last fsck: 4
```

A full `fsck` (forced via `/forcefsck` + reboot) did **not** clear
these — the identical block groups showed the identical corruption
immediately after remount, which is the signature of physically
failing SD card sectors, not a software-repairable filesystem issue.
The reboot also cost real data: `/opt/itsahomelab-banking-ops` (the
cloned repo) was gone afterward, most likely ext4's own orphan-inode
cleanup reclaiming files it considered inconsistent.

Decision: pulled `ITSaRevolution` out of `banking_app_nodes`
(`infra/ansible/inventory/hosts.yml`) rather than keep retrying a
~58MB/23-package Docker install onto degrading storage every 5 minutes
for a whole unattended weekend — the risk of worsening the corruption
or bricking the boot outweighed the value, especially with nobody home
to recover it. The Pi keeps `base-hardening` + `node-exporter`
(smaller footprint, and node-exporter's own dpkg blocker is now
cleared) so it still shows up in Grafana, but it's not carrying the
ledger-service this weekend. Re-add it once someone can check the SD
card by hand (health check or replacement) — this is a real residual
risk flagged, not silently dropped.

### GCP burst node stands in for the Pi in the two-node demo

`infra/terraform-gcp/` is a new, real (not skeleton) Terraform module:
a `google_compute_instance` (e2-micro), firewall rules for SSH/8000/
9100, and a `google_billing_budget` so an unattended weekend VM can't
run up a surprise bill. Same boot-to-enrolled pattern as the Proxmox
layer — it curls `bootstrap/enroll.sh` on first boot and self-enrolls.
This sandbox cannot `terraform apply` it (no GCP credentials, registry
blocked by the proxy) — see the module's README for the exact manual
steps the owner runs. `apps/ledger-service/run-demo.sh` is now
env-driven (`DEMO_NODES=...`) instead of hardcoding
`ITSaRevolution.local`, so the load-ramp demo runs against MorePower +
the GCP node without depending on home network reachability at all.

Done so far, in addition to the above: `apps/ledger-service/docker-compose.yml`
now has `restart: unless-stopped` on both services plus a real
healthcheck on the `ledger` service (previously: neither container
would come back on its own if a host rebooted while unattended).
Verified: `docker compose config` parses the restart/healthcheck
blocks correctly; yamllint clean. Full build+run verification happens
in CI same as always (this sandbox can't reach Docker Hub). A public
SSH key (same one already on `ITSaRevolution`) is now deployed via
`host_vars/smallrevolt.yml` too, so it's no longer the one machine
still on password auth — `base_hardening_ssh_lockdown` stays off on
both until key-based login is verified live with a second open
session, per this repo's standing lockout discipline.

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
