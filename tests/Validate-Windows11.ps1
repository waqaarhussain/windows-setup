#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Configure-Windows11.ps1')
foreach ($build in @(22000,22621,22631,26100,26200)) {
    if (-not (Test-Windows11Target $build 1 'AMD64')) { throw "Windows 11 x64 build $build rejected." }
}
if (Test-Windows11Target 19045 1 'AMD64') { throw 'Windows 10 accepted.' }
if (Test-Windows11Target 26100 3 'AMD64') { throw 'Windows Server accepted.' }
if (Test-Windows11Target 26100 2 'AMD64') { throw 'Domain controller accepted.' }
if (Test-Windows11Target 26100 1 'ARM64') { throw 'ARM64 accepted by an x64 installer.' }
if (Test-Windows11StartPinsSupport 22631 'Professional' $true) { throw 'Old build accepted for the new GPO.' }
if (Test-Windows11StartPinsSupport 26100 'Core' $true) { throw 'Home edition accepted for the managed policy.' }
if (Test-Windows11StartPinsSupport 26100 'Professional' $false) { throw 'Missing policy template ignored.' }
if (-not (Test-Windows11StartPinsSupport 26100 'Professional' $true)) { throw 'Supported policy capability rejected.' }
$root = Split-Path $PSScriptRoot
$manifest = Get-Content (Join-Path $root 'manifest.json') -Raw | ConvertFrom-Json
foreach ($required in @('scripts/Setup-Windows.ps1','scripts/Configure-Windows11.ps1','assets/StartPins.json','assets/TaskbarLayout.xml')) {
    if (-not $manifest.files.$required) { throw "Manifest missing $required" }
}
[xml]$taskbar = Get-Content (Join-Path $root 'assets/TaskbarLayout.xml') -Raw
if ($taskbar.SelectNodes("//*[local-name()='DefaultLayoutOverride']").Count) { throw 'Server/Windows 10 Start tile layout remains.' }
$pins = Get-Content (Join-Path $root 'assets/StartPins.json') -Raw | ConvertFrom-Json
if ($pins.pinnedList.Count -ne 0 -or -not $pins.applyOnce) { throw 'Unexpected Start pin configuration.' }
Write-Host 'PASS: Windows 11 target checks, Server/Windows 10 rejection, build/edition/template gates and shell assets.'
