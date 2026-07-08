# Runbook: enroll a new machine

**Goal**: a fresh machine joins the lab and starts self-reconciling
against this repo. Takes ~2 minutes of operator time.

## Steps

1. On the new machine (Debian/Ubuntu family, as root):

   ```sh
   curl -fsSL https://raw.githubusercontent.com/SigSegGit/ITSaHomeLab_Banking_Ops/main/bootstrap/enroll.sh -o /tmp/enroll.sh
   less /tmp/enroll.sh   # review what you're about to run
   sudo bash /tmp/enroll.sh
   ```

2. Watch the first reconcile pass complete:

   ```sh
   journalctl -u homelab-reconcile.service -f
   ```

   Expected: the `base-hardening` baseline applies and the run ends
   with the host's "reconciled at" confirmation line. The machine is
   now in the minimal `ungrouped` baseline.

3. **Assign it a job** (separate step, on purpose): commit its hostname
   into the right group in `infra/ansible/inventory/hosts.yml`. Within
   one pull interval (≤5 min) the machine picks up its new role on its
   own — do not SSH in to "help it."

4. If the machine will hold SOPS-encrypted values (M4+), place the
   lab's age key at `/etc/itsahomelab-banking-ops/age.key` by hand.
   This is the one step that never flows through Git — see
   `ARCHITECTURE.md`.

## Verify

- `systemctl list-timers | grep homelab` shows the reconcile timer armed.
- The next `git log` entry touching this host's group changes its
  config within ≤5 min, with no manual action.

## Rollback

Enrollment is just a timer + a clone: `systemctl disable --now
homelab-reconcile.timer && rm -rf /opt/itsahomelab-banking-ops` returns
the machine to unmanaged. See `decommission-a-machine.md` for the full
exit path.
