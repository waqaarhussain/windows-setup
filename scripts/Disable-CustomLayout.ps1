#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$policy = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
if (Test-Path $policy) {
    foreach ($name in @('StartLayoutFile','LockedStartLayout','ConfigureStartPins')) {
        Remove-ItemProperty -Path $policy -Name $name -ErrorAction SilentlyContinue
    }
}
Write-Host 'Custom Start/taskbar layout policy disabled for the current user.'
Write-Host 'Sign out and back in. This does not restore old pins or undo other setup settings.' -ForegroundColor Yellow
