# Windows RDP App

Eine Windows-Lernumgebung für Hochschulkurse. Alle Nutzer erhalten einen
eigenen lokalen Windows-Account auf einer gemeinsamen Windows-VM und greifen
per **Remote Desktop (RDP)** darauf zu.

Die App nutzt das bereits in OpenStack vorhandene Image
**„Windows 11 25H2 (UEFI)"** — es wird **kein** Packer-Image gebaut. Dadurch
entfällt die Build-Phase; deployt wird direkt per Terraform.

## User-Management

- **Ein Windows-Account pro Nutzer**, abgeleitet aus der E-Mail-Adresse
  (z. B. `erik.mueller@dhbw.de` → Benutzername `erikmueller`)
- Alle Nutzer aller Teams landen auf **einer gemeinsamen VM**
- Jeder Nutzer erhält ein automatisch generiertes, zufälliges Passwort
- Login per **RDP** (Port 3389) mit Benutzername + Passwort

## VM-Zugang

- **RDP-Port 3389** wird nach außen geöffnet (eigene Security Group, IPv4 + IPv6)
- Login z. B. per `mstsc /v:<ip>` (Windows) oder Microsoft Remote Desktop (macOS)
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
