# Windows RDP App

Eine Windows-Lernumgebung für Hochschulkurse. Alle Nutzer erhalten einen
eigenen lokalen Windows-Account auf einer gemeinsamen Windows-VM und greifen
per **Remote Desktop (RDP)** darauf zu.

Die App nutzt das bereits in OpenStack vorhandene Image
**„Windows 11 25H2 (UEFI)"** — es wird **kein** Packer-Image gebaut. Dadurch
entfällt die Build-Phase; deployt wird direkt per Terraform.

## Was macht diese App?

Pro Team wird **eine eigene Windows-11-VM** gestartet, die sich die Mitglieder
dieses Teams teilen. Jeder Nutzer bekommt seinen eigenen lokalen Windows-Account
(eigener Benutzername, eigenes Passwort) — Teammitglieder arbeiten auf derselben
Maschine, verschiedene Teams bekommen getrennte VMs. Die Gruppeneinteilung im
Deployment-Wizard (eine Gruppe / jeder Nutzer einzeln / individuell) bestimmt
damit direkt, wie viele VMs entstehen und wer sich eine Maschine teilt — genau
wie bei `template-app`.

Der Zugriff erfolgt per **Remote Desktop (RDP)**: Nutzer verbinden sich mit einem
RDP-Client (z. B. Microsoft Remote Desktop auf macOS) und sehen einen vollständigen
Windows-Desktop.

## User-Management

- **Ein Windows-Account pro Nutzer**, abgeleitet aus der E-Mail-Adresse
  (z. B. `erik.mueller@dhbw.de` → Benutzername `erikmueller`)
- Nutzer landen auf der VM ihres Teams — **eine VM pro Team**, geteilt von
  dessen Mitgliedern
- Jeder Nutzer erhält ein automatisch generiertes, zufälliges Passwort
- Login per **RDP** (Port 3389) mit Benutzername + Passwort
- Nutzer sind **Standard-User** (kein lokaler Administrator)

## Software

- **Visual Studio Code** wird auf jeder VM beim ersten Boot maschinenweit
  installiert (System-Installer, stille Installation via cloudbase-init) —
  steht damit allen lokalen Accounts auf dieser VM zur Verfügung.

## VM-Zugang

- **RDP-Port 3389** wird nach außen geöffnet (über eine vom Deployer gewählte Security Group mit RDP-Regel, IPv4 + IPv6)
- Zugriff primär per **IPv6** — funktioniert von überall ohne VPN
- Login z. B. per Microsoft Remote Desktop (macOS) oder `mstsc` (Windows)
- Zugangsdaten (Benutzername, Passwort, IP:Port) werden nach dem Deployment
  per E-Mail an die Nutzer versendet

## VM-Deployment

| | |
|---|---|
| VMs gesamt | **1 pro Team** |
| VMs pro Team | **1** (geteilt von allen Team-Mitgliedern) |
| VMs pro Nutzer | — |
| Image | `Windows 11 25H2 (UEFI)` (bestehendes Glance-Image) |
| Flavor | `win11.medium` (8 GB RAM, 2 vCPU, 80 GB) |
| Floating IP | Nein (feste Adresse ist öffentlich geroutet) |
| Security Group | vom Deployer im Wizard gewählt (muss RDP 3389 eingehend erlauben) |

## Konfigurierbare Variablen

| Variable | Beschreibung | Pflicht |
|---|---|---|
| `flavor_name` | Flavor der Windows-VM | Ja |
| `network_uuid` | UUID des internen Netzwerks | Ja |
| `floating_ip_pool` | Name des External Networks für Floating IPs | Nein |
| `shared_secgroup_id` | ID einer Security Group mit RDP-Freigabe (Port 3389, IPv4 + IPv6) | Ja |

## Deployment-Dauer

| Schritt | Dauer (ca.) |
|---|---|
| Packer Image Build | — (kein Packer) |
| Terraform apply | 3–5 min |
| Windows-Erststart + cloudbase-init (inkl. VS-Code-Installation) | 3–6 min |
| **Gesamt** | **6–11 min** |

> Hinweis: Nach `terraform apply` braucht Windows beim ersten Boot noch etwas
> Zeit, bis cloudbase-init die Benutzer angelegt, RDP aktiviert und VS Code
> installiert hat.

## Technische Hinweise

### IPv6-Konfiguration (statisch)

Das DHBWV6-Netz verwendet `ipv6_address_mode = dhcpv6-stateful`. Der DHBW-DHCPv6-Server
antwortet auf Windows-Gäste nicht zuverlässig. Daher wird die IPv6-Adresse **statisch**
konfiguriert:

1. Terraform legt **vor dem VM-Start** einen Neutron-Port an — dadurch ist die
   IPv6-Adresse bereits vor dem ersten Boot bekannt.
2. Die Adresse und der Gateway werden als Template-Variablen ans cloudbase-init-Script
   übergeben.
3. cloudbase-init setzt beim ersten Boot `New-NetIPAddress` + `New-NetRoute` statisch
   auf den VirtIO/TAP-Adapter.

Dies umgeht das Problem, dass `Get-NetAdapter -Physical` den VirtIO-Adapter nicht
erkennt und DHCPv6 auf Windows für dieses Netz nicht funktioniert.

### Windows-Sprachversion

Das cloudbase-init-Script verwendet **SIDs statt Gruppennamen**, um
unabhängig von der Windows-Sprachversion zu funktionieren:

- `S-1-5-32-555` = "Remote Desktop Users" (DE: "Remotedesktopbenutzer")
- `S-1-5-32-545` = "Users" (DE: "Benutzer")

Auf einem deutschen Windows würde `Add-LocalGroupMember -Group 'Remote Desktop Users'`
mit "Gruppe nicht gefunden" fehlschlagen. Die SID-basierte Lösung funktioniert
auf jeder Sprache.

### Firewall

Die RDP-Firewallgruppe wird über den **sprachunabhängigen Group-Token**
`@FirewallAPI.dll,-28752` aktiviert (nicht über `-DisplayGroup 'Remote Desktop'`,
das auf deutschem Windows ins Leere läuft). Zusätzlich werden explizite
Regeln für TCP und UDP 3389 auf allen Profilen angelegt.

### Benutzer-Aktivierung

Nach dem Anlegen wird jeder Account explizit aktiviert (`Enable-LocalUser`) und
`PasswordExpired = 0` gesetzt — damit wird verhindert, dass Windows beim ersten
RDP-Login einen Passwortwechsel erzwingt, was den Login blockieren würde.
