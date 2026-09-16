# Windows RDP App — Setup & Deployment Instructions

## Prerequisites

- Access to the DHBW OpenStack project
- OpenStack CLI configured (`clouds.yaml` or `OS_*` env vars)
- Terraform >= 1.0 installed
- Microsoft Remote Desktop (macOS: App Store or `brew install --cask microsoft-remote-desktop`)

---

## Quick redeploy & access (TL;DR)

```bash
cd terraform

# 1. Deploy
terraform apply -var='users={"team-a":[{"email":"user@dhbw.de"}]}'

# 2. Get IPv6 address and password (wait ~5 min after apply)
terraform output -json team_vms      # → fixed_ip_v6, rdp_target_v6
terraform output -json user_accounts # → auth (password)

# 3. Connect via RDP
# Microsoft Remote Desktop → Add PC → PC name: [2001:7c0:1b20:c913:1::xxxx]
# username: user   password: <auth value>

# 4. Destroy when done
terraform destroy -var='users={"team-a":[{"email":"user@dhbw.de"}]}'
```

---

## 1. What this app does

Deploys a shared **Windows 11 VM** on OpenStack. Each user gets a local Windows
account with a randomly generated password and can connect via **RDP (port 3389)**.

- No Packer build — uses the existing Glance image `Windows 11 25H2 (UEFI)` directly
- One shared VM for all users (all teams land on the same machine)
- App creates its own security group that opens TCP 3389 inbound (IPv4 + IPv6)
- cloudbase-init runs on first boot to create user accounts, enable RDP, and set IPv6
- VM gets both an IPv4 (`10.200.x.x`) and IPv6 (`2001:7c0:...`) address

---

## 2. Register in the AppStore

1. Push this repo to GitHub
2. If the repo is private: add collaborator `six7clickndeploy` (Settings → Collaborators)
3. Create a release tag: `git tag v1.0.0 && git push origin v1.0.0`
4. In the AppStore: **App hinzufügen** → paste the GitHub repo URL
5. The platform reads variables and Terraform config automatically

---

## 3. Test locally with Terraform

### Verify the image exists in Glance

```bash
openstack image show "Windows 11 25H2 (UEFI)"
```

### Verify the flavor exists

```bash
openstack flavor show win11.medium
```

### Init, plan, apply

```bash
cd terraform
terraform init
terraform plan -var='users={"test":[{"email":"test@dhbw.de"}]}'
terraform apply -var='users={"test":[{"email":"test@dhbw.de"}]}'
```

The dummy email only derives the username (`test@dhbw.de` → username `test`).

Plan shows **6 resources to create**:
- `random_password.user_passwords[0]`
- `openstack_networking_secgroup_v2.rdp`
- `openstack_networking_secgroup_rule_v2.rdp_v4`
- `openstack_networking_secgroup_rule_v2.rdp_v6`
- `openstack_networking_port_v2.vm_port`
- `openstack_compute_instance_v2.shared_vm`

### Get credentials (no email needed)

```bash
terraform output -json user_accounts
# shows username, password, ip, port
```

### Destroy after testing

```bash
terraform destroy -var='users={"test":[{"email":"test@dhbw.de"}]}'
```

---

## 4. Connect via RDP

**Wait 3–5 minutes** after `terraform apply` completes — cloudbase-init needs
to finish creating users, enabling RDP, and setting the IPv6 address on first boot.

### Via IPv6 — works from anywhere, no VPN needed

The VM gets a statically configured IPv6 address on first boot. Get it:

```bash
terraform output -json team_vms
# → "fixed_ip_v6": "2001:7c0:1b20:c913:1::xxxx"
# → "rdp_target_v6": "[2001:7c0:1b20:c913:1::xxxx]:3389"
```

**Microsoft Remote Desktop (macOS):**
1. **Add PC** → PC name: `[2001:7c0:1b20:c913:1::xxxx]` (with brackets, without `:3389`)
2. Add User Account → username `test`, password from `terraform output -json user_accounts`
3. Double-click → accept certificate warning → **Continue**

**Windows:**
```
mstsc /v:[2001:7c0:1b20:c913:1::xxxx]
```

### Via IPv4 — requires DHBW network or VPN

```bash
# Check reachability first:
ping 10.200.x.x
nc -zv 10.200.x.x 3389
```

Then connect to `10.200.x.x` in Microsoft Remote Desktop.

**Note:** Even on the DHBW network, IPv4 may not be routed to your device.
Use IPv6 whenever possible.

### Linux

```bash
xfreerdp /v:[2001:7c0:1b20:c913:1::xxxx] /u:test /p:<password>
```

---

## 5. How credentials reach users in the AppStore

When deployed via the AppStore (not locally), the platform sends each user a
credential email containing:

- IP address and port 3389
- Username (derived from email, dots removed: `erik.mueller` → `erikmueller`)
- Generated password

No manual `terraform output` step needed in production.

---

## 6. Variables reference

| Variable | Description | Default |
|---|---|---|
| `image_name` | Glance image name (platform-internal) | `Windows 11 25H2 (UEFI)` |
| `flavor_name` | OpenStack flavor | `win11.medium` |
| `network_uuid` | Internal network UUID | DHBWV6 network UUID |
| `floating_ip_pool` | External network name for floating IPs | `DHBW` |

`image_name` has a hardcoded default because this app has no Packer build —
the worker does not inject `image_name` for Packer-less apps.

---

## 7. How IPv6 works (technical background)

The DHBWV6 network uses `ipv6_address_mode = dhcpv6-stateful`. On Windows,
the DHCPv6 client does not reliably complete a lease on first boot for this
network. Additionally, `Get-NetAdapter -Physical` does not detect the VirtIO
TAP adapter used by OpenStack.

**Solution implemented:**

1. Terraform creates a **Neutron port explicitly** before the VM — this assigns
   the IPv6 address in Neutron's database before the instance starts.
2. The IPv6 address and gateway (`2001:7c0:1b20:c913::1`) are passed as
   template variables into the cloudbase-init PowerShell script.
3. On first boot, cloudbase-init sets the address **statically** using
   `New-NetIPAddress` and `New-NetRoute` on the first non-loopback adapter.

This is reliable and does not depend on DHCPv6.

---

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `terraform plan` fails on `data.openstack_images_image_v2.image` | Image name mismatch | Run `openstack image list` and correct `image_name` default in `variables.tf` |
| RDP error `0x204` (Unable to connect) | cloudbase-init still running | Wait 5 min after apply; check log (see below) |
| Login fails (wrong password) | cloudbase-init hasn't finished | Wait and retry; check log |
| Security group `windows-rdp-rdp` already exists | Previous partial deploy left it behind | Run `terraform destroy` or: `openstack security group delete windows-rdp-rdp` |
| RDP error `0x2407` (no permission) | User not in Remote Desktop Users group | See below |
| IPv6 address not set | cloudbase-init log shows "Kein passender Netzwerkadapter" | Check log; set manually via console |

### Check the cloudbase-init log

Open the VM console in OpenStack UI, then in PowerShell:

```powershell
type C:\cloudbase-init-app.log
```

Successful run looks like:
```
Starte App-Setup: Benutzer anlegen + RDP aktivieren + IPv6 binden
Benutzer 'test' angelegt
Benutzer 'test': aktiviert, PasswordExpired=0
fDenyTSConnections = 0 gesetzt (RDP erlaubt)
Firewall-Gruppe @FirewallAPI.dll,-28752 (RDP) aktiviert
Explizite Firewallregel AppStore-RDP-In-TCP angelegt
Explizite Firewallregel AppStore-RDP-In-UDP angelegt
TermService aktiviert und gestartet
IPv6-Adresse statisch gesetzt: 2001:7c0:1b20:c913:1::xxxx/64 auf tapXXXXXX
IPv6-Standardroute gesetzt: ::/0 via 2001:7c0:1b20:c913::1
App-Setup abgeschlossen
```

### Fix: user not in Remote Desktop Users group (0x2407)

Run in the OpenStack console (PowerShell as Administrator):

```powershell
# Language-independent (works on DE and EN Windows):
Add-LocalGroupMember -Group (Get-LocalGroup | Where-Object { $_.SID -eq 'S-1-5-32-555' }).Name -Member "test"
```

### Fix: IPv6 address missing (manual fallback)

Run in the OpenStack console (PowerShell as Administrator),
replacing the address with the value from `terraform output -json team_vms`:

```powershell
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Name -notlike 'Loopback*' } | Select-Object -First 1
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 -IPAddress "2001:7c0:1b20:c913:1::xxxx" -PrefixLength 64
New-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 -DestinationPrefix '::/0' -NextHop '2001:7c0:1b20:c913::1'
```
