# M2 skeleton: the resource shapes are real, the counts default to zero
# (see variables.tf: k8s_nodes = {}), so `plan` is a no-op until M2
# starts for real. Network design rationale: docs/network.md.

resource "proxmox_virtual_environment_vm" "k8s_node" {
  for_each = var.k8s_nodes

  name      = each.key
  node_name = var.proxmox_node

  clone {
    vm_id = var.vm_template_id
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory_mb
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk_gb
  }

  network_device {
    bridge  = "vmbr0"
    vlan_id = var.vlans.banking
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    # Boot straight into the M1 pull loop: the machine enrolls itself
    # against this repo on first boot, then the inventory decides what
    # it becomes. Terraform's responsibility ends here.
    user_data_file_id = proxmox_virtual_environment_file.enroll_snippet.id
  }
}

resource "proxmox_virtual_environment_file" "enroll_snippet" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    file_name = "homelab-enroll.yaml"
    data      = <<-EOF
      #cloud-config
      runcmd:
        - ["/bin/sh", "-c", "curl -fsSL ${var.enroll_url} | bash"]
    EOF
  }
}
