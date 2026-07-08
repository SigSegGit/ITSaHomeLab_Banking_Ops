terraform {
  required_version = ">= 1.6"

  required_providers {
    # Assumption flagged in README.md / ROADMAP.md: hypervisor is
    # Proxmox VE. Swap this provider if the real lab runs something else.
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  # Auth via PROXMOX_VE_API_TOKEN env var — never committed.
  insecure = var.proxmox_insecure_tls
}
