variable "datacenter_id" {
  description = "vSphere datacenter ID"
  type        = string
}

variable "datastore_id" {
  description = "Datastore ID for VM"
  type        = string
}

variable "resource_pool_id" {
  description = "Resource pool ID"
  type        = string
}

variable "network_id" {
  description = "Network ID for management interface"
  type        = string
}

variable "folder_path" {
  description = "VM folder path"
  type        = string
}

variable "ova_path" {
  description = "Path to Cloud Builder OVA"
  type        = string
}

variable "hostname" {
  description = "Hostname for Cloud Builder"
  type        = string
}

variable "domain" {
  description = "Domain name"
  type        = string
}

variable "num_cpus" {
  description = "Number of CPUs"
  type        = number
}

variable "memory_gb" {
  description = "Memory in GB"
  type        = number
}

variable "ip_address" {
  description = "IP address for Cloud Builder"
  type        = string
}

variable "netmask" {
  description = "Netmask (CIDR format)"
  type        = string
}

variable "gateway" {
  description = "Default gateway"
  type        = string
}

variable "dns_servers" {
  description = "List of DNS servers"
  type        = list(string)
}

variable "ntp_servers" {
  description = "List of NTP servers"
  type        = list(string)
}

variable "root_password" {
  description = "Root password"
  type        = string
  sensitive   = true
}

variable "admin_password" {
  description = "Admin password"
  type        = string
  sensitive   = true
}
