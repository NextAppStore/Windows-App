#ps1_sysnative
# Cloudbase-init runs this PowerShell block on first boot.
# Goal: create local Windows users and enable RDP + bind IPv6.

$ErrorActionPreference = "Stop"
$log = "C:\cloudbase-init-app.log"
function Log($m) { Add-Content -Path $log -Value "$(Get-Date -Format o)  $m" }

Log "Starte App-Setup: Benutzer anlegen + RDP aktivieren + IPv6 binden"

# --- Create local users ---------------------------------------------------
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
    # Do NOT force a password change at next logon (would otherwise block RDP)
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

# --- Enable RDP -----------------------------------------------------------
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
    Log "fDenyTSConnections = 0 gesetzt (RDP erlaubt)"

    # Language-independent RDP group (group token instead of DisplayGroup — works
    # in German and English; DisplayGroup 'Remote Desktop' would not match DE)
    Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752' -ErrorAction SilentlyContinue
    Log "Firewall-Gruppe @FirewallAPI.dll,-28752 (RDP) aktiviert"

    # Explicit safeguard: TCP+UDP 3389 on all profiles
    foreach ($proto in @('TCP', 'UDP')) {
        $rn = "AppStore-RDP-In-$proto"
        if (-not (Get-NetFirewallRule -Name $rn -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -Name $rn -DisplayName "RDP In (3389/$proto)" `
                -Direction Inbound -Protocol $proto -LocalPort 3389 -Action Allow `
                -Profile Domain, Private, Public
            Log "Explizite Firewallregel $rn angelegt"
        }
    }

    # Start/enable the RDP service
    Set-Service -Name TermService -StartupType Automatic
    Start-Service -Name TermService -ErrorAction SilentlyContinue
    Log "TermService aktiviert und gestartet"
} catch {
    Log "FEHLER bei RDP-Aktivierung: $_"
}

# --- Set IPv6 statically (DHCPv6-stateful is not answered by the DHBW server) ---
# The address is provided by Neutron/Terraform and written statically to the
# adapter here. This is more reliable than DHCPv6 on Windows.
try {
    $ipv6addr  = '${ipv6_address}'   # e.g. 2001:7c0:1b20:c913:1::2e3
    $ipv6gw    = '${ipv6_gateway}'   # e.g. 2001:7c0:1b20:c913::1
    $ipv6prefix = 64

    # Find the adapter (TAP/VirtIO — don't filter by -Physical)
    $adapter = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'Up' -and $_.Name -notlike 'Loopback*' } |
        Select-Object -First 1

    if ($adapter) {
        # Ensure the IPv6 protocol binding is enabled
        Enable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue

        # Remove any existing old address (idempotent)
        Remove-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 `
            -IPAddress $ipv6addr -ErrorAction SilentlyContinue

        # Set the static IPv6 address
        New-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 `
            -IPAddress $ipv6addr -PrefixLength $ipv6prefix -ErrorAction Stop
        Log "IPv6-Adresse statisch gesetzt: $ipv6addr/$ipv6prefix auf $($adapter.Name)"

        # Set the default route
        Remove-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 `
            -DestinationPrefix '::/0' -ErrorAction SilentlyContinue
        New-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 `
            -DestinationPrefix '::/0' -NextHop $ipv6gw -RouteMetric 10 -ErrorAction Stop
        Log "IPv6-Standardroute gesetzt: ::/0 via $ipv6gw"
    } else {
        Log "WARNUNG: Kein passender Netzwerkadapter gefunden"
    }

    # Status dump for verification
    $all6 = Get-NetIPAddress -AddressFamily IPv6 -ErrorAction SilentlyContinue |
        Select-Object InterfaceAlias, IPAddress, PrefixOrigin, SuffixOrigin, AddressState
    Log ("Get-NetIPAddress IPv6:`n" + ($all6 | Format-Table -AutoSize | Out-String))
} catch { Log "FEHLER bei IPv6-Konfiguration: $_" }

Log "App-Setup abgeschlossen"
