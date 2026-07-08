# Terraform layer (M2)

Provisions the lab's VMs and network topology. **Assumption flag** (also
in `ROADMAP.md`): this targets **Proxmox VE** via the `bpg/proxmox`
provider. If the actual hypervisor is something else, swap the provider
in `versions.tf` and rework `main.tf` — the variable surface
(`variables.tf`) and the network design (`../../docs/network.md`) are
hypervisor-agnostic on purpose.

Not applied anywhere yet — this is scaffolding until M2 starts for
real. `terraform fmt`/`validate` run in CI so the skeleton can't rot.

## State & credentials

- State stays **local** (`terraform.tfstate`, gitignored). A remote
  backend is overkill for a single-operator disposable lab, and state
  contains VM details that don't belong in a public repo.
- Provider credentials come from environment variables
  (`PROXMOX_VE_API_TOKEN`), never from committed files.
  `terraform.tfvars.example` documents every variable a real apply
  needs; copy to `terraform.tfvars` (gitignored) and fill in.

## Boot-to-enrolled flow

Every VM this layer creates cloud-inits straight into the M1 pull loop:

```
terraform apply
  └─ VM boots (cloud-init)
       └─ runs bootstrap/enroll.sh from this repo
            └─ machine self-reconciles forever (see ARCHITECTURE.md)
```

So Terraform's job ends at "a machine exists on the right network with
the right name" — everything about what the machine *does* is Ansible's
side of the house, driven by the inventory.
