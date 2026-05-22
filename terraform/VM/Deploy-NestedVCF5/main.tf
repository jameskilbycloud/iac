terraform {
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = ">= 2.13.0"
    }
  }
  required_version = ">= 1.0.0"
}

# Configure the vSphere Provider
provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}

# Data sources for vSphere infrastructure
data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

data "vsphere_datastore" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "management" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "esxi_management" {
  name          = var.esxi_management_network
  datacenter_id = data.vsphere_datacenter.dc.id

  depends_on = [module.networking]
}

# Create VM folder for nested VCF environment
resource "vsphere_folder" "vcf_folder" {
  path          = var.vm_folder
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Create resource pool for nested VCF
module "resource_pool" {
  source = "./modules/resource_pool"

  name               = var.resource_pool_name
  cluster_id         = data.vsphere_compute_cluster.cluster.resource_pool_id
  cpu_reservation    = var.resource_pool_cpu_reservation
  memory_reservation = var.resource_pool_memory_reservation
}

# Create VCF networking (port groups)
module "networking" {
  source = "./modules/networking"

  count = var.create_vcf_networks ? 1 : 0

  datacenter_id = data.vsphere_datacenter.dc.id
  cluster_id    = data.vsphere_compute_cluster.cluster.id
  vlan_ids      = var.vcf_vlan_ids
}

# Deploy nested ESXi hosts
module "esxi_hosts" {
  source = "./modules/esxi_hosts"

  count = var.esxi_count

  datacenter_id     = data.vsphere_datacenter.dc.id
  datastore_id      = data.vsphere_datastore.datastore.id
  resource_pool_id  = module.resource_pool.id
  network_id        = data.vsphere_network.esxi_management.id
  folder_path       = vsphere_folder.vcf_folder.path

  hostname          = "${var.esxi_hostname_prefix}-${count.index + 1}"
  domain            = var.esxi_domain
  num_cpus          = var.esxi_num_cpus
  num_cores_per_socket = var.esxi_num_cores_per_socket
  memory_mb         = var.esxi_memory_gb * 1024
  
  boot_disk_size_gb     = var.esxi_boot_disk_size_gb
  cache_disk_size_gb    = var.esxi_cache_disk_size_gb
  capacity_disk_size_gb = var.esxi_capacity_disk_size_gb

  root_password     = var.esxi_root_password
  management_ip     = length(var.esxi_management_ips) > 0 ? var.esxi_management_ips[count.index] : ""
  management_netmask = var.vcf_networks.management.netmask
  gateway           = var.vcf_networks.management.gateway
  dns_servers       = var.dns_servers

  depends_on = [module.networking]
}

# Deploy Cloud Builder VM
module "cloud_builder" {
  source = "./modules/cloud_builder"

  count = var.deploy_cloud_builder ? 1 : 0

  datacenter_id    = data.vsphere_datacenter.dc.id
  datastore_id     = data.vsphere_datastore.datastore.id
  resource_pool_id = module.resource_pool.id
  network_id       = data.vsphere_network.management.id
  folder_path      = vsphere_folder.vcf_folder.path

  ova_path         = var.cloud_builder_ova_path
  hostname         = var.cloud_builder_hostname
  domain           = var.esxi_domain
  num_cpus         = var.cloud_builder_num_cpus
  memory_gb        = var.cloud_builder_memory_gb

  ip_address       = var.cloud_builder_ip
  netmask          = var.cloud_builder_netmask
  gateway          = var.cloud_builder_gateway
  dns_servers      = var.dns_servers
  ntp_servers      = var.ntp_servers

  root_password    = var.cloud_builder_root_password
  admin_password   = var.cloud_builder_admin_password

  depends_on = [module.esxi_hosts]
}
