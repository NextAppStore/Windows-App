
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
  value = {
    for uid, user in local.users_map : uid => {
      type     = "password"
      authtype = "rdp"
      ip       = local.enable_floating_ip ? openstack_networking_floatingip_v2.team_fip[user.team].address : openstack_compute_instance_v2.team_vm[user.team].network[0].fixed_ip_v4
      port     = 3389
      username = user.username
      auth     = random_password.user_passwords[uid].result
      email    = user.email
      team     = user.team
    }
  }
}

############################
# VM Details
############################

# Note: the backend normalizer only recognizes `url`/`code_server_url` in
# team_vms as a clickable link. `rdp_command`/`rdp_target` are therefore
# purely informational — the actual credentials come from user_accounts.
output "team_vms" {
  description = "Details of each team's Windows VM and its users"
  value = {
    for team in local.unique_teams : team => {
      instance_id   = openstack_compute_instance_v2.team_vm[team].id
      instance_name = openstack_compute_instance_v2.team_vm[team].name
      fixed_ip      = openstack_compute_instance_v2.team_vm[team].network[0].fixed_ip_v4
      fixed_ip_v6   = local.fixed_ip_v6[team]
      floating_ip   = local.enable_floating_ip ? openstack_networking_floatingip_v2.team_fip[team].address : null
      rdp_target    = "${local.enable_floating_ip ? openstack_networking_floatingip_v2.team_fip[team].address : openstack_compute_instance_v2.team_vm[team].network[0].fixed_ip_v4}:3389"
      rdp_target_v6 = "[${local.fixed_ip_v6[team]}]:3389"
      users = [
        for uid, user in local.users_map : {
          username    = user.username
          team        = user.team
          rdp_command = "mstsc /v:${local.enable_floating_ip ? openstack_networking_floatingip_v2.team_fip[team].address : openstack_compute_instance_v2.team_vm[team].network[0].fixed_ip_v4}"
        }
        if user.team == team
      ]
    }
  }
}

output "teams_summary" {
  description = "Overview: number of VMs and users"
  value = {
    vm_count   = length(local.unique_teams)
    user_count = length(local.all_users)
    usernames  = local.usernames
    emails     = local.emails
    teams      = local.unique_teams
  }
}
