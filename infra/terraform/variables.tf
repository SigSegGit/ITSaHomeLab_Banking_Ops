variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint, e.g. https://pve.lab.local:8006/"
  type        = string
}

variable "proxmox_insecure_tls" {
  description = "Accept the hypervisor's self-signed certificate (typical for a homelab)"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name to place VMs on"
  type        = string
  default     = "pve"
}

variable "vm_template_id" {
  description = "ID of the cloud-init-enabled VM template to clone (e.g. a Debian 12 cloud image template)"
  type        = number
}

variable "enroll_url" {
  description = "Raw URL of bootstrap/enroll.sh in this repo — every VM runs it at first boot (see infra/terraform/README.md)"
  type        = string
  default     = "https://raw.githubusercontent.com/SigSegGit/ITSaHomeLab_Banking_Ops/main/bootstrap/enroll.sh"
}

# The segmented topology (docs/network.md). VLAN IDs are lab-local
# conventions; the segmentation *existing* is the point, the exact IDs
# are not.
variable "vlans" {
  description = "VLAN ID per network segment"
  type = object({
    management = number
    banking    = number
    ingress    = number
  })
  default = {
    management = 10
    banking    = 20
    ingress    = 30
  }
}

variable "k8s_nodes" {
  description = "Kubernetes node VMs to create (hostname => spec). Hostnames must match infra/ansible/inventory/hosts.yml group membership."
  type = map(object({
    cores     = number
    memory_mb = number
    disk_gb   = number
  }))
  default = {
    # Filled in when M2 starts for real, e.g.:
    # "k8s-1" = { cores = 2, memory_mb = 4096, disk_gb = 40 }
  }
}
