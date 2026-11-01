#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WinRARLicensePath,
    [string]$WinRARLicenseUrl = 'https://drive.google.com/uc?export=download&id=12IOtUoZZv3sCcHJuC-4Lz1lh76z_36fc',
    [switch]$SkipWinRARLicenseDownload,
    [switch]$SharingOnly,
    [switch]$FromLocalPackage
)

function Test-WinRARLicenseFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $content = [string](Get-Content -LiteralPath $Path -Raw)
    return ($content -match '\ARAR registration data\r?\n' -and $content -match '(?m)^UID=[^\r\n]+')
}

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess) {
    throw 'Run this in 64-bit Windows PowerShell 5.1.'
}
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open Windows PowerShell as Administrator, then run the installer again.'
}

$targetOS = Get-CimInstance Win32_OperatingSystem
if ($targetOS.ProductType -ne 1 -or [int]$targetOS.BuildNumber -lt 22000 -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw 'This repository targets Windows 11 x64. Use windows-server-setup for Windows Server.'
}

# Local licence files take priority. Otherwise use the configured download URL.
# The URL is public in this repository; licence bytes are not committed.
if (-not $WinRARLicensePath) {
    $candidates = @()
    if ($PSScriptRoot) { $candidates += Join-Path $PSScriptRoot 'rarreg.key' }
    $desktop = [Environment]::GetFolderPath('Desktop')
    if ($desktop) { $candidates += Join-Path $desktop 'rarreg.key' }
    $WinRARLicensePath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if ($WinRARLicensePath) {
    $WinRARLicensePath = (Resolve-Path -LiteralPath $WinRARLicensePath -ErrorAction Stop).ProviderPath
}

$stage = Join-Path $env:TEMP ('WindowsSetup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if ($FromLocalPackage) {
        if (-not $PSScriptRoot) { throw 'Run install.ps1 from the extracted package for local installation.' }
        $manifestPath = Join-Path $PSScriptRoot 'manifest.json'
    } else {
        # Resolve main once so the manifest and scripts come from the same immutable commit.
        $headers = @{ 'User-Agent' = 'windows-setup'; 'Accept' = 'application/vnd.github+json' }
        $commit = Invoke-RestMethod -Uri 'https://api.github.com/repos/waqaarhussain/windows-setup/commits/main' -Headers $headers
        $revision = [string]$commit.sha
        if ($revision -notmatch '^[a-f0-9]{40}$') { throw 'GitHub did not return a valid source commit.' }
        $baseUrl = "https://raw.githubusercontent.com/waqaarhussain/windows-setup/$revision"
        Write-Host "Source commit: $revision" -ForegroundColor Cyan
        $manifestPath = Join-Path $stage 'manifest.json'
        Invoke-WebRequest -Uri "$baseUrl/manifest.json" -UseBasicParsing -OutFile $manifestPath
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1) { throw 'Unsupported installer manifest.' }
    $files = @(
        'scripts/Setup-Windows.ps1',
        'scripts/Disable-CustomLayout.ps1',
        'scripts/Configure-Extras.ps1',
        'scripts/Configure-Windows11.ps1',
        'assets/StartPins.json',
        'assets/TaskbarLayout.xml',
        'scripts/Invoke-StorageCleanup.ps1',
        'scripts/Restore-OptionalServices.ps1'
    )
    foreach ($relative in $files) {
        $expected = [string]$manifest.files.$relative
        if ($expected -notmatch '^[a-fA-F0-9]{64}$') { throw "Missing or invalid checksum: $relative" }
        $destination = Join-Path $stage $relative
        New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
        if ($FromLocalPackage) {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $relative) -Destination $destination
        } else {
            Invoke-WebRequest -Uri "$baseUrl/$relative" -UseBasicParsing -OutFile $destination
        }
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $expected) {
            throw "Checksum mismatch: $relative. No setup script was run."
        }
    }

    if ($SharingOnly) {
        . (Join-Path $stage 'scripts/Configure-Extras.ps1')
        $repairLogs = Join-Path $env:ProgramData 'WindowsSetup\Logs'
        New-Item -ItemType Directory -Path $repairLogs -Force | Out-Null
        $repairLog = Join-Path $repairLogs ('Sharing-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
        Start-Transcript -Path $repairLog | Out-Null
        try {
            Enable-VpsNetworkSharing
            Write-Host "Sharing repair completed. Log: $repairLog" -ForegroundColor Green
            Write-Host 'Close and reopen Advanced sharing settings to check both switches.' -ForegroundColor Yellow
        } finally { Stop-Transcript | Out-Null }
        return
    }

    if (-not $WinRARLicensePath -and -not $SkipWinRARLicenseDownload) {
        $licenceUri = $null
        if (-not [uri]::TryCreate($WinRARLicenseUrl, [UriKind]::Absolute, [ref]$licenceUri) -or $licenceUri.Scheme -ne 'https') {
            throw 'The WinRAR licence download URL must be an absolute HTTPS URL.'
        }
        $WinRARLicensePath = Join-Path $stage 'rarreg.key'
        Invoke-WebRequest -Uri $licenceUri.AbsoluteUri -UseBasicParsing -OutFile $WinRARLicensePath -MaximumRedirection 10 -TimeoutSec 120
        Write-Host 'WinRAR licence download completed.'
    }
    if ($WinRARLicensePath -and -not (Test-WinRARLicenseFile -Path $WinRARLicensePath)) {
        throw 'The licence file is not in the expected WinRAR registration format. Google Drive may have returned a sign-in or confirmation page. No setup script was run.'
    }

    $restoreDir = Join-Path $env:ProgramData 'WindowsSetup'
    New-Item -ItemType Directory -Path $restoreDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $stage 'scripts/Disable-CustomLayout.ps1') -Destination $restoreDir -Force
    foreach ($helper in @('Configure-Extras.ps1','Restore-OptionalServices.ps1')) {
        Copy-Item -LiteralPath (Join-Path $stage "scripts/$helper") -Destination $restoreDir -Force
    }
    $setupArgs = @{}
    if ($WinRARLicensePath) { $setupArgs.WinRARLicensePath = $WinRARLicensePath }
    & (Join-Path $stage 'scripts/Setup-Windows.ps1') @setupArgs
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
