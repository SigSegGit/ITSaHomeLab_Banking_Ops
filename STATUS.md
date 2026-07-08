# Status

Read this first when resuming work cold.

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
