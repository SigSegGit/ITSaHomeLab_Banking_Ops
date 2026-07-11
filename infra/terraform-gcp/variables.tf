variable "project_id" {
  description = "GCP project ID (create it by hand first — see README.md; Terraform provisions inside it, not the project itself)"
  type        = string
}

variable "billing_account_id" {
  description = "Billing account ID (Billing console URL bar, format XXXXXX-XXXXXX-XXXXXX) to attach the budget alert to"
  type        = string
}

variable "region" {
  description = "GCP region for the burst node"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP zone for the burst node"
  type        = string
  default     = "europe-west1-b"
}

variable "instance_name" {
  description = "Instance name — must match a hostname in infra/ansible/inventory/hosts.yml so ansible-pull's --limit \"%H\" picks up the right group membership on first reconcile"
  type        = string
  default     = "gcp-burst-1"
}

variable "machine_type" {
  description = "e2-micro is in the GCP always-free tier (1 per eligible region) — deliberately the cheapest shape since this is a burst/demo node, not a workhorse"
  type        = string
  default     = "e2-micro"
}

variable "enroll_url" {
  description = "Raw URL of bootstrap/enroll.sh in this repo — the instance runs it once at first boot"
  type        = string
  default     = "https://raw.githubusercontent.com/SigSegGit/ITSaHomeLab_Banking_Ops/main/bootstrap/enroll.sh"
}

variable "ssh_public_key" {
  description = "Public key granted login at boot (same key as infra/ansible/inventory/host_vars/*.yml). Private key never belongs here."
  type        = string
}

variable "ssh_username" {
  description = "OS Login username the ssh_public_key metadata entry is created for"
  type        = string
  default     = "sigseg"
}

variable "budget_amount_usd" {
  description = "Monthly budget threshold in USD — this is a homelab burst node left running unattended over a weekend, keep it low"
  type        = number
  default     = 10
}
