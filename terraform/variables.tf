################################################
# REQUIRED variables (injected by the worker)
################################################

variable "users" {
  description = "Per-team roster — injected by the worker. @platform:internal"
  type = map(list(object({
    email = string
  })))
  default = {}
}

variable "image_name" {
  description = "Glance image name of the existing Windows image. @platform:internal"
  type        = string
  # Must exactly match the Glance image name. Since this app has no
  # Packer build, the worker does not set image_name — this default
  # is the actually used value.
  default = "Windows 11 25H2 (UEFI)"
}

################################################
# Configurable variables (in the AppStore wizard)
################################################

variable "flavor_name" {
  description = "Flavor of the Windows VM @openstack:flavor:name"
  type        = string
  default     = "win11.medium"
}

variable "network_uuid" {
  description = "Primary network @openstack:network:id"
  type        = string
  # TODO: placeholder (from the Ubuntu app). The deployer selects the actual
  # DHBWV6 network in the wizard; set the real UUID for correct defaults.
  default = "9b579624-d844-4df3-b38d-89978b31d37d"
}

variable "floating_ip_pool" {
  description = "Name des External Networks für Floating IPs @openstack:floating_ip_pool:name"
  type        = string
  default     = "DHBW"
}

variable "shared_secgroup_id" {
  description = "ID einer Security Group mit RDP-Freigabe (Port 3389, IPv4 + IPv6) @openstack:security_group:id"
  type        = string
  default     = "2b37d6a2-dd64-4ce1-9f4a-c6cc92e0d8ef"
}
