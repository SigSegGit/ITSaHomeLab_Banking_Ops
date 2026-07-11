# GCP burst-capacity node

Stands up one `e2-micro` GCE instance and enrolls it into the same
pull-loop as every other machine in this lab (`bootstrap/enroll.sh` on
first boot, then Ansible decides what it becomes via
`infra/ansible/inventory/hosts.yml`). Separate root module from
`../terraform` (Proxmox) on purpose — different provider, different
state, different credentials; no reason to force them into one apply.

Built for a specific real situation: `ITSaRevolution` (the Pi) has a
failing SD card (see `STATUS.md`) and was pulled from
`banking_app_nodes` rather than risk more writes to it. This node
takes its place in the two-node load-ramp demo, with the advantage of
a real public IP — no dependency on the home network or SSH tunnels to
demo against it.

## What Terraform does NOT do here

Project creation and billing enablement are **manual, one-time, GCP
console steps** — deliberately not in this module. Terraform providers
can create GCP projects, but doing so needs org/folder permissions
this lab doesn't assume exist, and the console flow is faster for a
single project than debugging Terraform's IAM prerequisites at 2am.

## One-time manual setup (do this first)

1. https://console.cloud.google.com/projectcreate — create a project,
   note its **project ID** (not its display name).
2. Enable billing on it: Billing → link a billing account. Note the
   **billing account ID** (format `XXXXXX-XXXXXX-XXXXXX`, shown in the
   Billing console URL/list).
3. Enable the two APIs this module needs:
   ```
   gcloud services enable compute.googleapis.com --project=<project-id>
   gcloud services enable billingbudgets.googleapis.com --project=<project-id>
   ```
4. Authenticate Terraform:
   ```
   gcloud auth application-default login
   ```

## Apply

```bash
cd infra/terraform-gcp
cp terraform.tfvars.example terraform.tfvars   # gitignored, fill in
terraform init
terraform plan
terraform apply
```

`terraform.tfvars` needs at minimum `project_id`, `billing_account_id`,
and `ssh_public_key` (reuse the same public key already committed in
`infra/ansible/inventory/host_vars/ITSaRevolution.yml` — private keys
never belong in this repo or in `.tfvars`).

`terraform output instance_external_ip` gives you the address to SSH
to and to add to `infra/ansible/inventory/hosts.yml` /
`host_vars/gcp-burst-1.yml` (mirroring the existing hosts — see those
files, `gcp-burst-1` is already wired into `banking_app_nodes`
alongside `MorePower`).

## State & credentials

Same posture as `../terraform`: state stays local (gitignored,
`*.tfstate`), never a remote backend for a single-operator disposable
lab. Credentials come from `gcloud auth application-default login` or
`GOOGLE_APPLICATION_CREDENTIALS`, never from a committed file.

## Cost

`e2-micro` is in GCP's always-free tier, but **only** in specific
regions (`us-west1`, `us-central1`, `us-east1`) — this module defaults
to `europe-west1` for latency to the rest of the lab, which is **not**
free-tier eligible. Expect a small real charge (a few dollars for a
weekend). The `google_billing_budget` resource alerts the billing
account's admins by email at 50%/90%/100% of `budget_amount_usd`
(default $10) — that's the actual safety net for "don't let an
unattended VM run up a bill nobody's watching," not the free tier.

## Tearing it down

```bash
terraform destroy
```

Remove `gcp-burst-1` from `hosts.yml`/`host_vars/` in the same commit
so nothing points ansible-pull at a machine that no longer exists.
