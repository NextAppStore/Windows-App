
############################
# [CONTRACT] User Accounts Output
############################

# Schema for user_accounts:
# "<team>-<username>": {
#   type     = "password"   # password | ssh_key | oauth | none
#   authtype = "rdp"        # RDP-only account, no SSH available
#   ip       = "1.2.3.4"
#   port     = 3389
#   username = "erik"
#   auth     = "<password>"
# }
# RDP credentials are transported via user_accounts — the credential mailer
# renders type="password" as a password line.

output "user_accounts" {
  description = "[CONTRACT] User accounts with RDP login information"
  sensitive   = true # Contains passwords
  value = length(local.all_users) > 0 ? {
    for i in range(length(local.all_users)) : local.user_ids[i] => {
      type     = "password"
      authtype = "rdp"
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

# Note: the backend normalizer only recognizes `url`/`code_server_url` in
# team_vms as a clickable link. `rdp_command`/`rdp_target` are therefore
# purely informational — the actual credentials come from user_accounts.
output "team_vms" {
  description = "Details of the shared Windows VM and all users"
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
  description = "Overview: number of VMs and users"
  value = {
    vm_count   = local.vm_count
    user_count = length(local.all_users)
    usernames  = local.usernames
    emails     = local.emails
    teams      = local.unique_teams
  }
}
