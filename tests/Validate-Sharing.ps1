#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Configure-Extras.ps1')

# Mock the network/service/firewall cmdlets. No real services or firewall rules change.
$script:Connections = @([pscustomobject]@{ InterfaceAlias='Test NIC'; NetworkCategory='Public'; IPv4Connectivity='Internet'; IPv6Connectivity='Disconnected' })
$script:SharingTestRules = @{}
foreach ($group in @('Network Discovery','File and Printer Sharing')) {
    $script:SharingTestRules[$group] = @(
        [pscustomobject]@{ Name="$group-In"; Direction='Inbound'; Enabled='False'; Profile='None'; RemoteAddress='Any' },
        [pscustomobject]@{ Name="$group-Out"; Direction='Outbound'; Enabled='False'; Profile='None'; RemoteAddress='NativeOutboundScope' }
    )
}
function Get-NetConnectionProfile { $script:Connections }
function Set-Service { [CmdletBinding()]param($Name,$StartupType) }
function Start-Service { [CmdletBinding()]param($Name) }
function Get-NetFirewallRule {
    [CmdletBinding()]param($DisplayGroup,$PolicyStore)
    $script:SharingTestRules[$DisplayGroup]
}
function Set-NetFirewallRule {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline)]$InputObject, $Enabled, [string[]]$Profile, [string]$RemoteAddress)
    process {
        if ($PSBoundParameters.ContainsKey('Enabled')) { $InputObject.Enabled = $Enabled.ToString() }
        if ($PSBoundParameters.ContainsKey('Profile')) { $InputObject.Profile = $Profile -join ', ' }
        if ($PSBoundParameters.ContainsKey('RemoteAddress')) { $InputObject.RemoteAddress = $RemoteAddress }
    }
}
Enable-VpsNetworkSharing
foreach ($groupRules in $script:SharingTestRules.Values) {
    foreach ($rule in $groupRules) {
        if ($rule.Enabled -ne 'True' -or $rule.Profile -ne 'Public') { throw 'Public sharing was skipped or not enabled.' }
        if ($rule.Direction -eq 'Inbound' -and $rule.RemoteAddress -ne 'LocalSubnet') { throw 'Inbound rule scope is too broad.' }
        if ($rule.Direction -eq 'Outbound' -and $rule.RemoteAddress -ne 'NativeOutboundScope') { throw 'Native outbound scope was changed.' }
    }
}
$script:Connections += @(
    [pscustomobject]@{ InterfaceAlias='Private NIC'; NetworkCategory='Private'; IPv4Connectivity='Internet'; IPv6Connectivity='Disconnected' },
    [pscustomobject]@{ InterfaceAlias='Domain NIC'; NetworkCategory='DomainAuthenticated'; IPv4Connectivity='Internet'; IPv6Connectivity='Disconnected' }
)
Enable-VpsNetworkSharing
foreach ($groupRules in $script:SharingTestRules.Values) {
    foreach ($rule in $groupRules) {
        foreach ($profile in @('Public','Private','Domain')) {
            if ($rule.Profile -notmatch $profile) { throw "Mixed-profile configuration lost $profile" }
        }
    }
}
Write-Host 'PASS: Public-only and mixed profiles enable all sharing rules; inbound scope and native outbound scopes are preserved.'
