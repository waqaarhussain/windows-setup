#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Configure-Extras.ps1')
$backup = Join-Path $env:ProgramData 'WindowsSetup\OptionalServices-before-setup.json'
if (-not (Test-Path $backup)) { throw 'Optional-service backup not found.' }
foreach ($entry in @(Get-Content -LiteralPath $backup -Raw | ConvertFrom-Json)) {
    if ($entry.Name -notin @(Get-VpsOptionalServiceNames)) { throw 'Unexpected service in backup.' }
    if (-not (Get-Service -Name $entry.Name -ErrorAction SilentlyContinue)) { continue }
    $start = switch ([int]$entry.Start) { 2 { 'Automatic' }; 3 { 'Manual' }; 4 { 'Disabled' }; default { throw 'Unexpected service startup type.' } }
    Set-Service -Name $entry.Name -StartupType $start
    New-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$($entry.Name)" -Name DelayedAutoStart -Value ([int]$entry.DelayedAutoStart) -PropertyType DWord -Force | Out-Null
    if ($entry.WasRunning -and $start -ne 'Disabled') { Start-Service -Name $entry.Name }
    Write-Host "Restored $($entry.Name) startup type to $start"
}
