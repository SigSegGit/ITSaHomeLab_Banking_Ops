# ITSaHomeLab_Banking_Ops

A disposable homelab that simulates the infrastructure-operations side of
a bank: network segmentation, IaC-provisioned platform, a small set of
"banking" workloads (ledger/payments/fraud-sim) as something realistic
to actually operate, observability, secrets management, backup/DR, and
a CI/CD pipeline that deploys all of it.

Built for interview prep, not production.

**Start with [`docs/OVERVIEW.md`](docs/OVERVIEW.md)** — a visual tour
(diagrams, no jargon walls) of how this repo acts as the lab's control
plane. Then [`ROADMAP.md`](ROADMAP.md) for the milestone plan and
exactly what each milestone changes in the infra, and
[`STATUS.md`](STATUS.md) for where things currently stand.

**Disposability note**: this repo is intentionally unprotected (no
branch protection, permissive license — see [`LICENSE`](LICENSE)) and
the lab itself will be torn down after the interview it's built for.
Nothing here should be treated as hardened or long-lived.

## Layout

```
ARCHITECTURE.md     the GitHub-as-nerve-center pull design — read this first
ROADMAP.md          milestones + their infra repercussions
STATUS.md           current state, updated as work lands
bootstrap/          enroll.sh: the one command that adds a machine to the lab
infra/              IaC: network, hypervisor/VM provisioning, platform
  terraform/          provisioning (VMs, networks, DNS)
  ansible/             configuration management every machine pulls + applies
apps/                the simulated banking workloads
observability/      monitoring/logging/alerting stack config
security/           secrets management, scanning, hardening baselines
.github/workflows/  CI: lint/validate IaC, build+test app images
docs/               architecture notes, diagrams, runbooks
```

## Quick start

Nothing is deployable yet — this is the M0 scaffold. Follow `STATUS.md`
for what's real vs. planned. Once M1 lands, adding a machine to the lab
will be: `curl -fsSL .../bootstrap/enroll.sh | sudo bash` (or review it
locally first, same thing) — see `ARCHITECTURE.md` for what that
actually sets up and why.
