# Roadmap

Milestones, in the order they need to land, each one naming exactly
what changes in the infra when it ships. See `ARCHITECTURE.md` for the
pull-based (GitOps) design this all sits on top of, and `STATUS.md` for
what's actually done vs. still planned.

Assumptions baked into the milestones below, flagged because they're
guesses standing in for specifics that haven't been confirmed yet:
hypervisor is **Proxmox VE** (the default homelab choice; swap
`infra/terraform/` provider if it's actually something else — ESXi,
bare metal, a cloud account), and "banking ops" is interpreted as
*simulated* banking workloads (a ledger/payments/fraud-scoring API) —
not real financial software, just enough of a realistic workload to
have something worth operating, monitoring, and breaking on purpose.

## M0 — Repo scaffold & governance

**Ships:** this repo. README, LICENSE (Unlicense — public domain,
matches "fully permissive, I don't care" and the lab's disposability),
`ROADMAP.md`, `STATUS.md`, `ARCHITECTURE.md`, empty directory
structure, a CI skeleton that lints whatever IaC exists (starts as a
no-op, grows teeth as `infra/` fills in).

**Infra repercussion:** none yet — no machine exists that talks to this
repo. This milestone is purely "the source of truth exists and has a
shape."

## M1 — The pull loop itself (the actual nerve-center mechanism)

**Ships:** `bootstrap/enroll.sh` (one-shot enrollment script), the
systemd timer + service it installs, `infra/ansible/site.yml` as a
real (if mostly empty) entrypoint, the inventory convention
(`hosts.yml`, `group_vars/`, `host_vars/`), and a first
`base-hardening` role (OS updates, the enrollment agent itself, a
minimal firewall baseline, an SSH config baseline) — the thing every
machine in the lab gets regardless of its job.

**Infra repercussion:** every machine you enroll from this point
forward starts self-reconciling every few minutes against whatever's
in this repo, unattended. This is the milestone where "push a commit"
starts actually changing real machines — everything after M1 is just
"what's inside the thing M1 built."

## M2 — Platform layer: network segmentation + the Kubernetes cluster

**Ships:** `infra/terraform/` stands up the VMs and networks (a
segmented topology: management/ops VLAN, a "banking" application VLAN,
a DMZ-style ingress segment — the segmentation itself is half the
interview-relevant content here), and an Ansible role that turns a
group of those VMs into a small Kubernetes cluster (k3s — lightweight,
fast to stand up and tear down, which matters given the lab is
disposable) plus an ingress controller and a container registry.

**Infra repercussion:** `terraform apply` provisions/changes the VMs
and network topology directly; the new hosts enroll via M1's mechanism
the moment they boot (cloud-init calls `bootstrap/enroll.sh`), and
picking up the `k8s-node` group from `hosts.yml` is what turns a bare
VM into a cluster member — no manual step in between.

## M3 — The banking workloads, deployed GitOps-style

**Ships (started early, docker-compose stepping stone):**
`apps/ledger-service` — a real FastAPI + Postgres ledger (accounts,
deposit/withdraw/transfer, transaction history, a Prometheus `/metrics`
endpoint feeding straight into M4's dashboard), deployed via
`docker compose` on `banking_app_nodes` (the Pi and MorePower, on
purpose — not the Freebox VM, which stays dedicated to monitoring so
the load comparison isn't confounded). `apps/ledger-service/load-
generator.py` ramps request rate against a running instance, deliberate
about creating a visible bottleneck rather than describing one.
A Flux/Argo CD controller watching `apps/` directly (so "deploying a
new version" becomes "merge to main," no manual step) is real M3 infra
work that needs `k8s_node`s to exist first — docker-compose is the
pragmatic stand-in until that milestone actually starts, not a
substitute for it.

**Infra repercussion:** this is where the two reconciliation loops from
`ARCHITECTURE.md` (Ansible-pull for hosts, GitOps controller for
containers) start running side by side, and where a real HA/DR story
becomes necessary for the first time — a stateful ledger service needs
a real answer for "what happens when a node dies," which is exactly
the kind of question this milestone exists to have an answer for.
**Half-answered already**: `docs/runbooks/ledger-backup-restore.md` is
the tested recovery path for a dead node's *data*; a live node
automatically taking over a dead node's *traffic* (real replication,
failover) is the harder half still open — see that runbook's "known
gap" section.

## M4 — Observability & security posture

**Ships:** Prometheus + Grafana + Loki (metrics, dashboards, logs) as
another GitOps-deployed app; vulnerability scanning wired into CI for
every container image built under `apps/`; SOPS-encrypted secrets (see
`ARCHITECTURE.md`) replacing any plaintext placeholder values still
lying around from M2/M3; a documented, actually-tested backup/restore
procedure for the ledger service's data.

**Infra repercussion:** every machine and workload from M1–M3 gains a
monitoring agent / scrape target as a side effect of being in the
inventory at all (a `group_vars/all.yml` default, not a per-service
opt-in) — this is the milestone that proves the earlier ones were built
with observability in mind rather than bolted on after.

## M5 — CI/CD maturity & failure drills

**Ships:** CI grows from "lint" to "lint, `terraform plan` on every PR,
`ansible-lint` + a syntax-check dry run, container image build + scan +
push"; a documented, scheduled chaos/game-day exercise (kill a node,
watch M2's HA design and M4's alerting actually catch it) with results
written up in `docs/`.

**Infra repercussion:** this is the milestone whose entire point is to
*exercise* the infra rather than add to it — a clean run here is the
strongest evidence the whole lab actually demonstrates what it's meant
to for the interview, not just that it boots.
