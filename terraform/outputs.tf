
############################
# [CONTRACT] User Accounts Output
############################

# Schema user_accounts:
# "<team>-<username>": {
#   type     = "password"   # password | ssh_key | oauth | none
#   ip       = "1.2.3.4"
#   port     = 3389
#   username = "erik"
#   auth     = "<passwort>"
# }
# Die RDP-Zugangsdaten werden ueber user_accounts transportiert — der
# Credential-Mailer rendert type="password" als Passwort-Zeile.

output "user_accounts" {
  description = "[CONTRACT] User accounts mit RDP-Login-Informationen"
  sensitive   = true # Enthält Passwörter
  value = length(local.all_users) > 0 ? {
    for i in range(length(local.all_users)) : local.user_ids[i] => {
      type     = "password"
      ip       = local.enable_floating_ip ? openstack_networking_floatingip_v2.fip[0].address : openstack_compute_instance_v2.shared_vm.network[0].fixed_ip_v4
      port     = 3389
      username = local.usernames[i]
      auth     = random_password.user_passwords[i].result
      email    = local.emails[i]
      team     = local.all_users[i].team
    }
  } : {}
}

############################
# VM Details
############################

# Hinweis: Der Backend-Normalizer erkennt in team_vms nur `url`/`code_server_url`
# als klickbaren Link. `rdp_command`/`rdp_target` sind daher rein informativ —
# die eigentlichen Zugangsdaten kommen aus user_accounts.
output "team_vms" {
  description = "Details der gemeinsamen Windows-VM und aller Benutzer"
  value = local.vm_count > 0 ? {
    shared_vm = {
      instance_id   = openstack_compute_instance_v2.shared_vm.id
      instance_name = openstack_compute_instance_v2.shared_vm.name
      fixed_ip      = openstack_compute_instance_v2.shared_vm.network[0].fixed_ip_v4
      fixed_ip_v6   = local.fixed_ip_v6
      floating_ip   = local.enable_floating_ip ? openstack_networking_floatingip_v2.fip[0].address : null
      rdp_target    = "${local.enable_floating_ip ? openstack_networking_floatingip_v2.fip[0].address : openstack_compute_instance_v2.shared_vm.network[0].fixed_ip_v4}:3389"
      rdp_target_v6 = "[${local.fixed_ip_v6}]:3389"
      users = [for i in range(length(local.all_users)) : {
        username    = local.usernames[i]
        team        = local.all_users[i].team
        rdp_command = "mstsc /v:${local.enable_floating_ip ? openstack_networking_floatingip_v2.fip[0].address : openstack_compute_instance_v2.shared_vm.network[0].fixed_ip_v4}"
      }]
    }
  } : {}
}

output "teams_summary" {
  description = "Übersicht: Anzahl VMs und User"
  value = {
    vm_count   = local.vm_count
    user_count = length(local.all_users)
    usernames  = local.usernames
    emails     = local.emails
    teams      = local.unique_teams
  }
}
