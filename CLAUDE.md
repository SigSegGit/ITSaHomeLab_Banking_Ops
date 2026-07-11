# Project memory for Claude Code sessions

## THE MISSION — read this first, it overrides any other framing

This repo exists to demonstrate **Database Reliability Engineer skill**
for a real interview at **Revolut, Monday**. The specific things that
must be demonstrable, live, in ~10-12 minutes:

1. **Patroni-managed PostgreSQL HA** — a real cluster (leader +
   replica(s)), `patronictl list` showing streaming replication.
2. **Automatic failover** — kill the leader under live app load, watch
   Patroni promote a replica automatically, near-zero application
   errors during the switchover.
3. **Elastic ramp-up/down via IaC** — add/remove a replica node
   (Terraform + Ansible), watch it join/leave the cluster cleanly (no
   orphaned replication slots).
4. **Real performance monitoring** — Prometheus + Grafana showing
   replication lag, leader/replica role, and app throughput, visible
   *during* the failover/ramp demo, not just as static screenshots.

Deliberate scope cuts made under time pressure (see STATUS.md for
when/why) — do not silently re-expand these without checking with the
owner first: Patroni's own built-in Raft DCS instead of a separate
etcd quorum; the existing `apps/ledger-service` reused as the
transactional app instead of a new bespoke app; 2 nodes (MorePower +
a GCP burst node) rather than a wider mesh, with `ITSaRevolution` (Pi)
added back only once its SD card is confirmed stable (see the
`hosts.yml` comment — it was pulled out after confirmed hardware
corruption).

If you find yourself building anything that isn't in service of the 4
numbered points above, stop and check it's actually needed.

Read `STATUS.md` first, always — it's the running, honest log of what's
actually been built and verified vs. what's only statically checked.
Then `ARCHITECTURE.md` (the pull-model design and its reasoning) and
`ROADMAP.md` (milestones, each naming its exact infra repercussion).
`docs/OVERVIEW.md` has the visual tour if you need the shape of the
whole thing fast.

## Non-negotiables carried across every session on this repo

- **Verify before pushing, always** — this repo's entire history is
  "static lint alone missed real bugs" (see STATUS.md's M1 entries:
  two separate broken `--limit` fixes shipped before the real one).
  ansible-lint (production profile) + `ansible-playbook --syntax-check`
  + yamllint are the floor, not the ceiling — run real code wherever
  you can (this authoring sandbox has apt/Python/Docker; use them).
- **This sandbox's egress proxy blocks Docker Hub's CDN** (CloudFront
  presigned URLs reject the TLS-interception) and the Terraform
  registry. GitHub Actions CI has open network — that's where the
  actual `docker build`/`terraform validate` get proven. Don't treat a
  local pull failure here as a real bug without checking CI.
- **Never commit a real secret or a working credential**, even ones
  the owner pastes in chat "because it's disposable" — public keys are
  fine to commit (that's the point of them), private keys and
  passwords are not, regardless of what's said about the lab being
  temporary.
- **Push directly to `main` is authorized** (no branch protection, no
  PR requirement) — but `git fetch origin main` and fast-forward
  before every push; other sessions (human or agent) have pushed
  directly to this repo mid-session before. Check `git log
  origin/main` for surprises before assuming your local state is current.
- **Toggle-gated settings in `base-hardening` (SSH lockdown, firewall)
  default OFF for a reason**: this role runs unattended on real
  machines via the pull loop. Flipping one is a deliberate, reasoned
  inventory commit — verify a working alternate access path exists
  *before* the commit that could remove the one you're using, not
  after.

## Current real-world state (update this section as it changes)

Three machines enrolled: `ITSaRevolution` (Raspberry Pi 4B),
`smallrevolt` (VM on the Freebox router, always-on), `MorePower` (VM on
the owner's laptop — **only reachable when the laptop is home**).
`smallrevolt` hosts monitoring (Prometheus+Grafana); `ITSaRevolution`
and `MorePower` run the `apps/ledger-service` workload.

**`ITSaRevolution` and `smallrevolt` are exposed to the internet** via
router port-forwards (external 22101→22 on the Pi, external 22102→22
on `smallrevolt`) so the owner can reach them while away from home.
`smallrevolt` does **not** yet have an `ansible.posix.authorized_key`
entry in its inventory host_vars — it's still on password auth. Do not
enable `base_hardening_ssh_lockdown` for it without first confirming a
working key-based login, in a *second* terminal, before closing the
one you used to deploy the key.
