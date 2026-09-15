#ps1_sysnative
# Cloudbase-init fuehrt diesen PowerShell-Block beim ersten Boot aus.
# Ziel: lokale Windows-Benutzer anlegen und RDP aktivieren.

$ErrorActionPreference = "Stop"
$log = "C:\cloudbase-init-app.log"
function Log($m) { Add-Content -Path $log -Value "$(Get-Date -Format o)  $m" }

Log "Starte App-Setup: Benutzer anlegen + RDP aktivieren"

# --- Lokale Benutzer anlegen ---------------------------------------------
%{ for idx, user in all_users ~}
try {
    $pw = ConvertTo-SecureString '${passwords[idx]}' -AsPlainText -Force
    if (Get-LocalUser -Name '${user.username}' -ErrorAction SilentlyContinue) {
        Set-LocalUser -Name '${user.username}' -Password $pw
        Log "Benutzer '${user.username}' existierte, Passwort gesetzt"
    } else {
        New-LocalUser -Name '${user.username}' -Password $pw -FullName '${user.email}' -Description 'Click-n-Deploy user' -PasswordNeverExpires -AccountNeverExpires
        Log "Benutzer '${user.username}' angelegt"
    }
    Add-LocalGroupMember -Group 'Remote Desktop Users' -Member '${user.username}' -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group 'Users' -Member '${user.username}' -ErrorAction SilentlyContinue
} catch {
    Log "FEHLER bei Benutzer '${user.username}': $_"
}
%{ endfor ~}

# --- RDP aktivieren ------------------------------------------------------
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
    Log "fDenyTSConnections = 0 gesetzt (RDP erlaubt)"

    # NLA aktiviert lassen (sicherer); Standard-RDP-Firewallgruppe oeffnen
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
    Log "Firewall-Gruppe 'Remote Desktop' aktiviert"

    # Explizite Regel als Absicherung (falls die Gruppe fehlt)
    if (-not (Get-NetFirewallRule -Name 'AppStore-RDP-In' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'AppStore-RDP-In' -DisplayName 'RDP In (3389)' -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow
        Log "Explizite Firewallregel fuer TCP 3389 angelegt"
    }

    # RDP-Dienst starten/aktivieren
    Set-Service -Name TermService -StartupType Automatic
    Start-Service -Name TermService -ErrorAction SilentlyContinue
    Log "TermService aktiviert und gestartet"
} catch {
    Log "FEHLER bei RDP-Aktivierung: $_"
}

Log "App-Setup abgeschlossen"
