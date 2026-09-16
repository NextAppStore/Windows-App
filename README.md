# Windows RDP App

Eine Windows-Lernumgebung für Hochschulkurse. Alle Nutzer erhalten einen
eigenen lokalen Windows-Account auf einer gemeinsamen Windows-VM und greifen
per **Remote Desktop (RDP)** darauf zu.

Die App nutzt das bereits in OpenStack vorhandene Image
**„Windows 11 25H2 (UEFI)"** — es wird **kein** Packer-Image gebaut. Dadurch
entfällt die Build-Phase; deployt wird direkt per Terraform.

## Was macht diese App?

Es wird **eine einzelne Windows-11-VM** gestartet, die sich **alle Nutzer teilen**.
Jeder Nutzer bekommt seinen eigenen lokalen Windows-Account (eigener Benutzername,
eigenes Passwort) — aber alle arbeiten auf derselben Maschine. Das spart Ressourcen
und ist für Lehr-Szenarien gedacht, bei denen alle Teilnehmer die gleiche Umgebung
brauchen (z. B. eine Software ausprobieren, eine Übung durchführen).

Der Zugriff erfolgt per **Remote Desktop (RDP)**: Nutzer verbinden sich mit einem
RDP-Client (z. B. Microsoft Remote Desktop auf macOS) und sehen einen vollständigen
Windows-Desktop.

## User-Management

- **Ein Windows-Account pro Nutzer**, abgeleitet aus der E-Mail-Adresse
  (z. B. `erik.mueller@dhbw.de` → Benutzername `erikmueller`)
- Alle Nutzer aller Teams landen auf **einer gemeinsamen VM**
- Jeder Nutzer erhält ein automatisch generiertes, zufälliges Passwort
- Login per **RDP** (Port 3389) mit Benutzername + Passwort
- Nutzer sind **Standard-User** (kein lokaler Administrator)

## VM-Zugang

- **RDP-Port 3389** wird nach außen geöffnet (eigene Security Group, IPv4 + IPv6)
- Zugriff primär per **IPv6** — funktioniert von überall ohne VPN
- Login z. B. per Microsoft Remote Desktop (macOS) oder `mstsc` (Windows)
- Zugangsdaten (Benutzername, Passwort, IP:Port) werden nach dem Deployment
  per E-Mail an die Nutzer versendet

## VM-Deployment

| | |
|---|---|
| VMs gesamt | **1** (geteilt von allen Teams und Nutzern) |
| VMs pro Team | — |
| VMs pro Nutzer | — |
| Image | `Windows 11 25H2 (UEFI)` (bestehendes Glance-Image) |
| Flavor | `win11.medium` (8 GB RAM, 2 vCPU, 80 GB) |
| Floating IP | Nein (feste Adresse ist öffentlich geroutet) |
| Security Group | wird von der App erstellt (RDP 3389 eingehend) |

## Konfigurierbare Variablen

| Variable | Beschreibung | Pflicht |
|---|---|---|
| `flavor_name` | Flavor der Windows-VM | Ja |
| `network_uuid` | UUID des internen Netzwerks | Ja |
| `floating_ip_pool` | Name des External Networks für Floating IPs | Nein |

## Deployment-Dauer

| Schritt | Dauer (ca.) |
|---|---|
| Packer Image Build | — (kein Packer) |
| Terraform apply | 3–5 min |
| Windows-Erststart + cloudbase-init | 2–5 min |
| **Gesamt** | **5–10 min** |

> Hinweis: Nach `terraform apply` braucht Windows beim ersten Boot noch etwas
> Zeit, bis cloudbase-init die Benutzer angelegt und RDP aktiviert hat.

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
