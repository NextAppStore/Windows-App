################################################
# PFLICHT-Variablen (vom Worker injiziert)
################################################

variable "users" {
  description = "Per-team roster — vom Worker injiziert. @platform:internal"
  type = map(list(object({
    email = string
  })))
  default = {}
}

variable "image_name" {
  description = "Glance-Image-Name des bestehenden Windows-Images. @platform:internal"
  type        = string
  # Muss exakt dem Glance-Image-Namen entsprechen. Da diese App keinen
  # Packer-Build hat, wird kein image_name vom Worker gesetzt — dieser
  # Default ist der tatsaechlich verwendete Wert.
  default = "Windows 11 25H2 (UEFI)"
}

################################################
# Konfigurierbare Variablen (im AppStore-Wizard)
################################################

variable "flavor_name" {
  description = "Flavor der Windows-VM @openstack:flavor:name"
  type        = string
  default     = "win11.medium"
}

variable "network_uuid" {
  description = "Hauptnetzwerk @openstack:network:id"
  type        = string
  # TODO: Platzhalter (aus Ubuntu-App). Der Deployer waehlt das echte
  # DHBWV6-Netzwerk im Wizard; fuer korrekte Defaults die echte UUID setzen.
  default = "9b579624-d844-4df3-b38d-89978b31d37d"
}

variable "floating_ip_pool" {
  description = "Name des External Networks für Floating IPs @openstack:floating_ip_pool:name"
  type        = string
  default     = "DHBW"
}
