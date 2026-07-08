# Architecture: GitHub as the nerve center

The whole point of this lab: **this repo is the single source of truth
every machine reconciles itself against.** Nobody pushes config out to
machines — every machine pulls, on its own schedule, and applies
whatever it finds. Adding a new machine to the lab means pointing it at
this repo, not touching any existing machine or any central "push"
controller.

This is deliberately a pull model, not push, for two reasons: (1) a
push system (a controller with SSH/WinRM credentials to every machine)
is itself a piece of infra that has to be built, secured, and kept
alive — one more thing to demo and one more thing to break; (2) it's
the closer analogue to what a bank's real platform team runs (GitOps),
so it's the more interview-relevant thing to build anyway.

## Why a public, unprotected repo makes this simpler, not riskier

Every machine just needs `git clone`/`git pull` — no deploy key, no PAT,
no secret to provision on day one of a new VM's life. That's the whole
reason the repo is public: it turns "how does a brand new machine
authenticate to fetch its config" from a real problem into a non-issue.
The trade-off this accepts (config as public information; nothing
in-repo is ever a real secret — see below) is fine for a disposable
interview lab and would not be an acceptable trade-off for anything
long-lived, which is exactly why `STATUS.md` and `README.md` both say
this loudly.

## Two reconciliation loops, one per workload shape

- **Bare hosts/VMs — `ansible-pull`.** Every non-Kubernetes machine
  (hypervisor host, jump box, monitoring host, whatever) runs a systemd
  timer (`homelab-reconcile.timer`, installed by
  `bootstrap/enroll.sh`) that does `git pull` against this repo, then
  `ansible-playbook -i localhost, --connection=local infra/ansible/site.yml
  --limit "$(hostname)"`. The playbook is data-driven off
  `infra/ansible/inventory/host_vars/<hostname>.yml` /
  `group_vars/<group>.yml`, so "what does this machine become" is a
  matter of which group it's in, not a special-cased script.
- **Everything containerized — GitOps via Flux/ArgoCD (M3).** Once the
  Kubernetes platform milestone lands, workloads under `apps/` are
  reconciled by an in-cluster controller watching this repo directly,
  same principle applied to the containerized half of the lab.

Both loops converge on the same rule: **the repo is the desired state;
a machine that drifts from it self-heals on its next pull**, typically
every 5–15 minutes (tunable per group — see `infra/ansible/group_vars`).

## Machine enrollment (the actual "let any machine join" mechanism)

A brand new machine joins the lab by running `bootstrap/enroll.sh`
(reviewed before running, but designed to be a single command — see the
script's header comment). It:
1. Installs `git` + `ansible` if missing.
2. Clones this repo to `/opt/itsahomelab-banking-ops`.
3. Installs and enables the systemd timer + service that repeats
   step 2 (`git pull`) and then runs `site.yml` scoped to its own
   hostname, forever, unattended.
4. Does **not** need the machine added to any inventory *before*
   enrolling — see `infra/ansible/inventory/hosts.yml`'s dynamic
   grouping convention (M1): a host that isn't explicitly listed falls
   into a minimal `ungrouped` baseline (updates, monitoring agent,
   nothing banking-specific) until someone assigns it a real group in
   a follow-up commit. Enrolling a machine and deciding what it's *for*
   are two separate, independently-timed steps on purpose.

## What never goes in this repo

Real secrets don't live here in plaintext, public repo or not — that's
not a "because it's public" carve-out, it's just correct regardless.
Where a value must be secret (banking-workload DB passwords, any real
credential), it's SOPS-encrypted in place (`infra/ansible/**/*.sops.yml`)
so the plaintext file layout — and therefore "what config exists" —
stays fully readable to every machine and every person, while the
values themselves need the lab's age/GPG key to decrypt. That key is
never itself committed; each machine gets it once at enrollment time,
out of band (see `bootstrap/enroll.sh`'s `SOPS_AGE_KEY` step), not via
`git pull`. This is the one deliberate exception to "everything flows
through the pull loop," because it's the one thing that structurally
can't.

## Directory conventions this depends on

```
infra/ansible/
  ansible.cfg
  site.yml                 entrypoint: includes every role, gated by group
  inventory/
    hosts.yml               static groups (hypervisors, banking-app hosts, ...)
    group_vars/<group>.yml  "what a group of machines becomes"
    host_vars/<host>.yml    per-host overrides (rare — group is the norm)
  roles/                    one role per concern (base-hardening, monitoring-agent, ...)
```

A machine's identity is `hostname` + "which groups is it in" — nothing
more exotic than standard Ansible inventory, on purpose: it's the part
of this design that has to be instantly legible to anyone reviewing the
repo, including an interviewer.
