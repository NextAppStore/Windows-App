terraform {
  required_version = ">= 1.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "openstack" {
  cloud = "openstack"
  # Auth via OS_CLOUD + clouds.yaml (oder OS_* env vars)
}

############################
# APP-DEFAULTS (vom App-Entwickler vorgegeben)
############################

locals {
  app_name = "windows-rdp"

  # Adressen in DHBWv4 sind oeffentlich geroutet, die feste Adresse der
  # Instanz ist also fuer sich erreichbar. Kein Floating IP noetig.
  enable_floating_ip = false

  metadata = {}
}

############################
# USER MANAGEMENT (CONTRACT)
############################

# Flatten users from teams — EXAKT wie im Contract vorgegeben.
locals {
  all_users = flatten([
    for team, members in var.users : [
      for member in members : {
        id    = "${team}-${replace(split("@", member.email)[0], ".", "-")}"
        team  = team
        email = member.email
        # Windows-Benutzername: keine Punkte (Windows-freundlich)
        username = replace(split("@", member.email)[0], ".", "")
      }
    ]
  ])

  unique_teams = distinct([for user in local.all_users : user.team])

  # Eine gemeinsame VM fuer alle Nutzer
  vm_count = 1

  usernames = [for user in local.all_users : user.username]
  emails    = [for user in local.all_users : user.email]
  user_ids  = [for user in local.all_users : user.id]

  # IPv6-Adresse aus dem explizit angelegten Port lesen.
  # Wir filtern nach dem IPv6-Subnetz damit die Reihenfolge keine Rolle spielt.
  fixed_ip_v6 = try([
    for fa in openstack_networking_port_v2.vm_port.all_fixed_ips :
    fa if can(regex(":", fa))
  ][0], "")

  # IPv6-Gateway des DHBWV6-Subnetzes (fest; aendert sich nicht)
  ipv6_gateway = "2001:7c0:1b20:c913::1"
}

# Ein Passwort pro User. override_special ist auf Zeichen beschraenkt, die in
# PowerShell-Interpolation und RDP unproblematisch sind (kein $, `, ", ').
resource "random_password" "user_passwords" {
  count            = length(local.all_users)
  length           = 16
  special          = true
  override_special = "!@#%^*_-+="
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

# Bestehendes Glance-Image per Name laden (kein Packer-Build noetig).
data "openstack_images_image_v2" "image" {
  name        = var.image_name
  most_recent = true
}

# External network nur noetig, wenn Floating IP aktiviert ist.
data "openstack_networking_network_v2" "external" {
  count = local.enable_floating_ip ? 1 : 0
  name  = var.floating_ip_pool
}

############################
# SECURITY GROUP (RDP)
############################

# Eigene Security Group, damit die App unabhaengig von bestehenden Gruppen
# funktioniert. Oeffnet eingehend RDP (3389) fuer IPv4 und IPv6.
resource "openstack_networking_secgroup_v2" "rdp" {
  name        = "${local.app_name}-rdp"
  description = "Allow inbound RDP (3389) for the Windows app"
}

resource "openstack_networking_secgroup_rule_v2" "rdp_v4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3389
  port_range_max    = 3389
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.rdp.id
}

resource "openstack_networking_secgroup_rule_v2" "rdp_v6" {
  direction         = "ingress"
  ethertype         = "IPv6"
  protocol          = "tcp"
  port_range_min    = 3389
  port_range_max    = 3389
  remote_ip_prefix  = "::/0"
  security_group_id = openstack_networking_secgroup_v2.rdp.id
}

# -----------------------------------------------------------------------------
# Netzwerk-Port explizit anlegen — so kennen wir die IPv6-Adresse VOR dem
# VM-Start und koennen sie in user_data (cloudbase-init) einbetten.
# -----------------------------------------------------------------------------
resource "openstack_networking_port_v2" "vm_port" {
  name               = "${local.app_name}-port"
  network_id         = var.network_uuid
  security_group_ids = [openstack_networking_secgroup_v2.rdp.id]
  admin_state_up     = true
}

# -----------------------------------------------------------------------------
# Shared Windows VM
# -----------------------------------------------------------------------------
resource "openstack_compute_instance_v2" "shared_vm" {
  name        = "${local.app_name}-shared"
  image_id    = data.openstack_images_image_v2.image.id
  flavor_name = var.flavor_name
  key_pair    = null

  security_groups = [openstack_networking_secgroup_v2.rdp.name]

  timeouts {
    create = "15m"
    delete = "15m"
  }

  network {
    port = openstack_networking_port_v2.vm_port.id
  }

  # Cloudbase-init fuehrt den PowerShell-Block beim ersten Boot aus:
  # legt lokale Benutzer an und aktiviert RDP.
  user_data = templatefile("${path.module}/cloudbase-init.txt.tpl", {
    all_users    = local.all_users
    passwords    = [for p in random_password.user_passwords : p.result]
    ipv6_address = local.fixed_ip_v6
    ipv6_gateway = local.ipv6_gateway
  })

  metadata = merge(local.metadata, {
    teams  = join(",", local.unique_teams)
    users  = join(",", local.usernames)
    emails = join(",", local.emails)
  })
}

# -----------------------------------------------------------------------------
# Optional Floating IP (eine fuer die gemeinsame VM)
# -----------------------------------------------------------------------------
resource "openstack_networking_floatingip_v2" "fip" {
  count = local.enable_floating_ip ? 1 : 0
  pool  = data.openstack_networking_network_v2.external[0].name
}

resource "openstack_networking_floatingip_associate_v2" "fip_assoc" {
  count       = local.enable_floating_ip ? 1 : 0
  floating_ip = openstack_networking_floatingip_v2.fip[0].address
  port_id     = openstack_compute_instance_v2.shared_vm.network[0].port

  depends_on = [openstack_compute_instance_v2.shared_vm]
}
