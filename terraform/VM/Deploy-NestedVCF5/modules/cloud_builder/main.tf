# Deploy Cloud Builder VM from OVA
resource "vsphere_virtual_machine" "cloud_builder" {
  name             = "${var.hostname}.${var.domain}"
  resource_pool_id = var.resource_pool_id
  datastore_id     = var.datastore_id
  folder           = var.folder_path

  num_cpus = var.num_cpus
  memory   = var.memory_gb * 1024
  guest_id = "other4xLinux64Guest"
  firmware = "efi"

  network_interface {
    network_id   = var.network_id
    adapter_type = "vmxnet3"
  }

  ovf_deploy {
    local_ovf_path       = var.ova_path
    disk_provisioning    = "thin"
    ip_protocol          = "IPv4"
    ip_allocation_policy = "static"
    
    ovf_network_map = {
      "Network 1" = var.network_id
    }
  }

  vapp {
    properties = {
      "guestinfo.hostname"      = var.hostname
      "guestinfo.ip0"           = var.ip_address
      "guestinfo.netmask0"      = var.netmask
      "guestinfo.gateway"       = var.gateway
      "guestinfo.dns"           = join(",", var.dns_servers)
      "guestinfo.domain"        = var.domain
      "guestinfo.searchpath"    = var.domain
      "guestinfo.ntp"           = join(",", var.ntp_servers)
      "guestinfo.rootPassword"  = var.root_password
      "guestinfo.adminPassword" = var.admin_password
    }
  }

  lifecycle {
    ignore_changes = [
      annotation
    ]
  }
}
