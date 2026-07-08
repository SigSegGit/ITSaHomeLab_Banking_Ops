# Runbook: decommission a machine

**Goal**: remove a machine from the lab cleanly, in the right order —
inventory first, machine second, so the pull loop never resurrects
config on a box that's leaving.

## Steps

1. **Remove it from the inventory first**: delete its hostname from
   every group in `infra/ansible/inventory/hosts.yml` (and any
   `host_vars/<hostname>.yml`), commit, push. The machine's next
   reconcile pass drops it back to the bare `ungrouped` baseline.

2. On the machine, stop the pull loop and remove the clone:

   ```sh
   sudo systemctl disable --now homelab-reconcile.timer
   sudo rm -f /etc/systemd/system/homelab-reconcile.{service,timer}
   sudo systemctl daemon-reload
   sudo rm -rf /opt/itsahomelab-banking-ops
   ```

3. If it held the SOPS age key: `sudo rm -rf /etc/itsahomelab-banking-ops`.
   If there's any suspicion the key leaked with the machine (sold,
   recycled, lost), rotate the lab key and re-encrypt — the key is
   lab-wide, not per-machine, by design (disposable lab trade-off).

4. If Terraform created the machine, remove its entry from
   `k8s_nodes` (or the relevant map) in `terraform.tfvars` and
   `terraform apply` — that destroys the VM itself.

## Verify

- `systemctl list-timers | grep homelab` on the machine: empty.
- The hostname appears nowhere in `infra/ansible/inventory/`.
- CI on the removal commit is green (a hostname referenced by a
  play/group that no longer exists would fail ansible-lint's syntax
  pass).
