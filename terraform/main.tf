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
  # Auth via OS_CLOUD + clouds.yaml (or OS_* env vars)
}

############################
# APP DEFAULTS (set by the app developer)
############################

locals {
  app_name = "windows-rdp"

  # Addresses in DHBWv4 are publicly routed, so the instance's fixed address
  # is reachable on its own. No floating IP needed.
  enable_floating_ip = false

  metadata = {}
}

############################
# USER MANAGEMENT (CONTRACT)
############################

# Flatten users from teams — EXACTLY as specified by the contract.
locals {
  all_users = flatten([
    for team, members in var.users : [
      for member in members : {
        id    = "${team}-${replace(split("@", member.email)[0], ".", "-")}"
        team  = team
        email = member.email
        # Windows username: no dots (Windows-friendly)
        username = replace(split("@", member.email)[0], ".", "")
      }
    ]
  ])

  unique_teams = distinct([for user in local.all_users : user.team])

  users_map = { for user in local.all_users : user.id => user }

  usernames = [for user in local.all_users : user.username]
  emails    = [for user in local.all_users : user.email]

  # Read the IPv6 address from each team's explicitly created port.
  # We filter by the IPv6 subnet so ordering doesn't matter.
  fixed_ip_v6 = {
    for team in local.unique_teams : team => try([
      for fa in openstack_networking_port_v2.team_port[team].all_fixed_ips :
      fa if can(regex(":", fa))
    ][0], "")
  }

  # IPv6 gateway of the DHBWV6 subnet (fixed; does not change)
  ipv6_gateway = "2001:7c0:1b20:c913::1"
}

# One password per user. override_special is restricted to characters that
# are safe in PowerShell interpolation and RDP (no $, `, ", ').
resource "random_password" "user_passwords" {
  for_each         = local.users_map
  length           = 16
  special          = true
  override_special = "!@#%^*_-+="
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

# Load the existing Glance image by name (no Packer build needed).
data "openstack_images_image_v2" "image" {
  name        = var.image_name
  most_recent = true
}

# External network only needed if floating IP is enabled.
data "openstack_networking_network_v2" "external" {
  count = local.enable_floating_ip ? 1 : 0
  name  = var.floating_ip_pool
}

# -----------------------------------------------------------------------------
# Explicitly create one network port per team — this way we know each team's
# IPv6 address BEFORE its VM starts and can embed it in user_data
# (cloudbase-init).
# -----------------------------------------------------------------------------
resource "openstack_networking_port_v2" "team_port" {
  for_each           = toset(local.unique_teams)
  name               = "${local.app_name}-${each.key}-port"
  network_id         = var.network_uuid
  security_group_ids = [var.shared_secgroup_id]
  admin_state_up     = true
}

# -----------------------------------------------------------------------------
# One Windows VM per team, shared by that team's members
# -----------------------------------------------------------------------------
resource "openstack_compute_instance_v2" "team_vm" {
  for_each = toset(local.unique_teams)

  name        = "${local.app_name}-${each.key}"
  image_id    = data.openstack_images_image_v2.image.id
  flavor_name = var.flavor_name
  key_pair    = null

  # Security group is already set via team_port.security_group_ids
  # (var.shared_secgroup_id, chosen by the deployer in the wizard). No
  # additional `security_groups` here — that would be a name-based reference,
  # which breaks with a 409 "Multiple security_group matches found" when
  # multiple groups with the same name exist in the project.

  timeouts {
    create = "15m"
    delete = "15m"
  }

  network {
    port = openstack_networking_port_v2.team_port[each.key].id
  }

  # Cloudbase-init runs the PowerShell block on first boot: creates this
  # team's local users, enables RDP, binds the static IPv6 address, and
  # installs VS Code.
  user_data = templatefile("${path.module}/cloudbase-init.txt.tpl", {
    team_users = [
      for uid, user in local.users_map : {
        username = user.username
        email    = user.email
        password = random_password.user_passwords[uid].result
      }
      if user.team == each.key
    ]
    ipv6_address = local.fixed_ip_v6[each.key]
    ipv6_gateway = local.ipv6_gateway
  })

  metadata = merge(local.metadata, {
    team = each.key
    app  = local.app_name
  })
}

# -----------------------------------------------------------------------------
# Optional floating IPs (one per team VM)
# -----------------------------------------------------------------------------
resource "openstack_networking_floatingip_v2" "team_fip" {
  for_each = local.enable_floating_ip ? toset(local.unique_teams) : toset([])
  pool     = data.openstack_networking_network_v2.external[0].name
}

resource "openstack_networking_floatingip_associate_v2" "team_fip_assoc" {
  for_each = local.enable_floating_ip ? toset(local.unique_teams) : toset([])

  floating_ip = openstack_networking_floatingip_v2.team_fip[each.key].address
  port_id     = openstack_networking_port_v2.team_port[each.key].id

  depends_on = [openstack_compute_instance_v2.team_vm]
}
