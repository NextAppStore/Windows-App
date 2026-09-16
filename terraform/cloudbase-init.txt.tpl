#ps1_sysnative
# Cloudbase-init fuehrt diesen PowerShell-Block beim ersten Boot aus.
# Ziel: lokale Windows-Benutzer anlegen und RDP aktivieren + IPv6 binden.

$ErrorActionPreference = "Stop"
$log = "C:\cloudbase-init-app.log"
function Log($m) { Add-Content -Path $log -Value "$(Get-Date -Format o)  $m" }

Log "Starte App-Setup: Benutzer anlegen + RDP aktivieren + IPv6 binden"

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
    Enable-LocalUser -Name '${user.username}' -ErrorAction SilentlyContinue
    # Passwort NICHT beim naechsten Logon erzwingen (blockiert sonst RDP)
    $adsi = [ADSI]"WinNT://./${user.username},user"
    $adsi.PasswordExpired = 0
    $adsi.SetInfo()
    Log "Benutzer '${user.username}': aktiviert, PasswordExpired=0"
    Add-LocalGroupMember -Group (Get-LocalGroup | Where-Object { $_.SID -eq 'S-1-5-32-555' }).Name -Member '${user.username}' -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group (Get-LocalGroup | Where-Object { $_.SID -eq 'S-1-5-32-545' }).Name -Member '${user.username}' -ErrorAction SilentlyContinue
} catch {
    Log "FEHLER bei Benutzer '${user.username}': $_"
}
%{ endfor ~}

# --- RDP aktivieren ------------------------------------------------------
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
    Log "fDenyTSConnections = 0 gesetzt (RDP erlaubt)"

    # Sprachunabhaengige RDP-Gruppe (Group-Token statt DisplayGroup — funktioniert
    # auf deutsch und englisch; DisplayGroup 'Remote Desktop' wuerde DE nicht treffen)
    Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752' -ErrorAction SilentlyContinue
    Log "Firewall-Gruppe @FirewallAPI.dll,-28752 (RDP) aktiviert"

    # Explizite Absicherung: TCP+UDP 3389 auf allen Profilen
    foreach ($proto in @('TCP', 'UDP')) {
        $rn = "AppStore-RDP-In-$proto"
        if (-not (Get-NetFirewallRule -Name $rn -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -Name $rn -DisplayName "RDP In (3389/$proto)" `
                -Direction Inbound -Protocol $proto -LocalPort 3389 -Action Allow `
                -Profile Domain, Private, Public
            Log "Explizite Firewallregel $rn angelegt"
        }
    }

    # RDP-Dienst starten/aktivieren
    Set-Service -Name TermService -StartupType Automatic
    Start-Service -Name TermService -ErrorAction SilentlyContinue
    Log "TermService aktiviert und gestartet"
} catch {
    Log "FEHLER bei RDP-Aktivierung: $_"
}

# --- IPv6 statisch setzen (DHCPv6-stateful beantwortet der DHBW-Server nicht) ---
# Die Adresse wird von Neutron/Terraform bekannt gegeben und hier statisch
# auf den Adapter geschrieben. Das ist zuverlaessiger als DHCPv6 auf Windows.
try {
    $ipv6addr  = '${ipv6_address}'   # z.B. 2001:7c0:1b20:c913:1::2e3
    $ipv6gw    = '${ipv6_gateway}'   # z.B. 2001:7c0:1b20:c913::1
    $ipv6prefix = 64

    # Adapter finden (TAP/VirtIO — nicht -Physical filtern)
    $adapter = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'Up' -and $_.Name -notlike 'Loopback*' } |
        Select-Object -First 1

    if ($adapter) {
        # IPv6-Protokollbindung sicherstellen
        Enable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue

        # Eventuell vorhandene alte Adresse entfernen (idempotent)
        Remove-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 `
            -IPAddress $ipv6addr -ErrorAction SilentlyContinue

        # Statische IPv6-Adresse setzen
        New-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 `
            -IPAddress $ipv6addr -PrefixLength $ipv6prefix -ErrorAction Stop
        Log "IPv6-Adresse statisch gesetzt: $ipv6addr/$ipv6prefix auf $($adapter.Name)"

        # Default-Route setzen
        Remove-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 `
            -DestinationPrefix '::/0' -ErrorAction SilentlyContinue
        New-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 `
            -DestinationPrefix '::/0' -NextHop $ipv6gw -RouteMetric 10 -ErrorAction Stop
        Log "IPv6-Standardroute gesetzt: ::/0 via $ipv6gw"
    } else {
        Log "WARNUNG: Kein passender Netzwerkadapter gefunden"
    }

    # Status-Dump zur Verifikation
    $all6 = Get-NetIPAddress -AddressFamily IPv6 -ErrorAction SilentlyContinue |
        Select-Object InterfaceAlias, IPAddress, PrefixOrigin, SuffixOrigin, AddressState
    Log ("Get-NetIPAddress IPv6:`n" + ($all6 | Format-Table -AutoSize | Out-String))
} catch { Log "FEHLER bei IPv6-Konfiguration: $_" }

Log "App-Setup abgeschlossen"
