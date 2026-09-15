# Windows RDP App — Setup & Deployment Instructions

## Prerequisites

- Access to the DHBW OpenStack project
- OpenStack CLI configured (`clouds.yaml` or `OS_*` env vars)
- Terraform >= 1.0 installed
- Microsoft Remote Desktop (macOS: `brew install --cask microsoft-remote-desktop`)

---

## Quick redeploy & access (TL;DR)

```bash
cd Windows-App/terraform

# 1. Deploy
terraform apply -var='users={"test":[{"email":"test@dhbw.de"}]}'

# 2. Get IPv6 address (wait ~5 min after apply first)
terraform output -json team_vms
# → look for "fixed_ip_v6", e.g. "2001:7c0:1b20:c913:1::xxxx"

# 3. Get password
terraform output -json user_accounts
# → look for "auth" field

# 4. Connect via RDP (no VPN needed — works from anywhere with IPv6)
# Microsoft Remote Desktop → Add PC → PC name: [2001:7c0:1b20:c913:1::xxxx]
# username: test   password: <auth value>

# 5. Destroy when done
terraform destroy -var='users={"test":[{"email":"test@dhbw.de"}]}'
```

---

## 1. What this app does

Deploys a shared **Windows 11 VM** on OpenStack. Each user gets a local Windows
account with a randomly generated password and can connect via **RDP (port 3389)**.

- No Packer build — uses the existing Glance image `Windows 11 25H2 (UEFI)` directly
- One shared VM for all users (all teams land on the same machine)
- App creates its own security group that opens TCP 3389 inbound (IPv4 + IPv6)
- cloudbase-init runs on first boot to create user accounts and enable RDP
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

Plan shows **5 resources to create**:
- `random_password.user_passwords[0]`
- `openstack_networking_secgroup_v2.rdp`
- `openstack_networking_secgroup_rule_v2.rdp_v4`
- `openstack_networking_secgroup_rule_v2.rdp_v6`
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
to finish creating users and enabling RDP on first boot.

### Via IPv6 — works from anywhere, no VPN needed

The VM gets an IPv6 address automatically on the DHBW network. Get it:

```bash
terraform output -json team_vms
# → "fixed_ip_v6": "2001:7c0:1b20:c913:1::xxxx"
# → "rdp_target_v6": "[2001:7c0:1b20:c913:1::xxxx]:3389"
```

**Microsoft Remote Desktop (macOS):**
1. **Add PC** → PC name: `[2001:7c0:1b20:c913:1::xxxx]` (with brackets)
2. Double-click → username `test`, password from `terraform output -json user_accounts`
3. Accept certificate warning → **Continue**

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

### Linux (either IPv4 or IPv6)

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
| `network_uuid` | Internal network UUID | `9b579624-...` (DHBWV6) |
| `floating_ip_pool` | External network name for floating IPs | `DHBW` |

`image_name` has a hardcoded default because this app has no Packer build —
the worker does not inject `image_name` for Packer-less apps.

---

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `terraform plan` fails on `data.openstack_images_image_v2.image` | Image name mismatch | Run `openstack image list` and correct `image_name` default in `variables.tf` |
| RDP error `0x204` (Unable to connect) | cloudbase-init still running, or no IPv6 | Wait 5 min after apply; try IPv4 on VPN as fallback |
| `ping 10.200.x.x` times out | Not on DHBW network/VPN | Use IPv6 address instead (no VPN needed) |
| Login fails (wrong password) | cloudbase-init hasn't finished | Wait and retry; check OpenStack console for boot progress |
| Security group `windows-rdp-rdp` already exists | Previous partial deploy left it behind | Run `terraform destroy` or: `openstack security group delete windows-rdp-rdp` |
