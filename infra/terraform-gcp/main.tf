# Burst-capacity node for banking_app_nodes: stood up when local
# hardware isn't reliable enough to trust unattended (see STATUS.md —
# ITSaRevolution pulled out over a failing SD card), or whenever the
# lab wants a genuinely independent third node for the load-ramp demo.
# Same boot-to-enrolled flow as the Proxmox layer (../terraform):
# Terraform's job ends at "a machine exists and can reach the repo" —
# everything about what it *does* is Ansible's side of the house.

# Reserved (not ephemeral) so Prometheus' scrape config
# (monitoring_cloud_scrape_targets) can point at a stable address
# instead of one that changes on every stop/start.
resource "google_compute_address" "burst_node_ip" {
  name   = "${var.instance_name}-ip"
  region = var.region
}

resource "google_compute_instance" "burst_node" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone

  # e2-micro's always-free quota is per-region, tied to specific
  # regions (us-west1/us-central1/us-east1) — europe-west1 is NOT
  # free-tier eligible even on e2-micro. Left as the default anyway
  # (proximity to the rest of the lab, which is in France) — this is a
  # cost/latency tradeoff to make deliberately, not a mistake, so it's
  # flagged here rather than silently defaulting to a "free" region
  # that's slow for everyone actually using the lab. See README.md.
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.burst_node_ip.address
    }
  }

  metadata = {
    ssh-keys       = "${var.ssh_username}:${var.ssh_public_key}"
    startup-script = <<-EOF
      #!/bin/sh
      # Runs once per boot; enroll.sh itself is idempotent, so a
      # restart re-running this is harmless.
      curl -fsSL ${var.enroll_url} | bash
    EOF
  }

  tags = ["homelab-burst-node"]

  labels = {
    purpose = "homelab-banking-ops-burst"
  }
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.instance_name}-allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"] # operator is traveling, no fixed source IP
  target_tags   = ["homelab-burst-node"]
}

resource "google_compute_firewall" "allow_lab_services" {
  name    = "${var.instance_name}-allow-lab-services"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["8000", "9100"] # ledger-service, node-exporter
  }

  # Same disposable-lab posture as the rest of this repo (see
  # CLAUDE.md) — not a real production boundary, but still scoped to a
  # tag rather than every instance in the project.
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["homelab-burst-node"]
}

# Default behavior (no all_updates_rule/notification channel below):
# GCP emails the billing account's admins/users automatically at each
# threshold. No Pub/Sub topic or extra plumbing needed for that alone
# — appropriate here since the whole point is "don't let an unattended
# VM run up a bill nobody's watching," not building a paging pipeline.
resource "google_billing_budget" "burst_node_budget" {
  billing_account = var.billing_account_id
  display_name    = "${var.instance_name} weekend budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }
}

output "instance_external_ip" {
  value       = google_compute_address.burst_node_ip.address
  description = <<-EOF
    Reserved (stable) IP. SSH here: ssh <ssh_username>@<this-ip>.
    Also add as "<this-ip>:9100" to
    infra/ansible/roles/monitoring-stack/defaults/main.yml's
    monitoring_cloud_scrape_targets (or override in
    host_vars/smallrevolt.yml) so Grafana picks it up.
  EOF
}
