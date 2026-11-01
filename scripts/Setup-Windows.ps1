#Requires -Version 5.1
[CmdletBinding()]
param([string]$WinRARLicensePath)

# Windows 11 x64 VPS Setup Toolkit
# Run in an interactive, elevated Windows PowerShell 5.1 session.
# WinRAR licensing uses an optional local rarreg.key file; no licence is embedded.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'Configure-Extras.ps1')
. (Join-Path $PSScriptRoot 'Configure-Windows11.ps1')

if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell 5.1.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$admin = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run PowerShell as Administrator.' }
if ($identity.IsSystem) { throw 'Run as the interactive Administrator account, not SYSTEM.' }
$os = Get-CimInstance Win32_OperatingSystem
if (-not (Test-Windows11Target -BuildNumber ([int]$os.BuildNumber) -ProductType ([int]$os.ProductType) -Architecture $env:PROCESSOR_ARCHITECTURE)) {
    throw "This setup requires Windows 11 x64 (workstation build 22000+). Detected $($os.Caption) / $($os.BuildNumber) / $env:PROCESSOR_ARCHITECTURE."
}
if ($WinRARLicensePath -and -not (Test-Path -LiteralPath $WinRARLicensePath -PathType Leaf)) { throw 'The supplied WinRAR licence file does not exist.' }
$root = Join-Path $env:ProgramData 'WindowsSetup'
$logDir = Join-Path $root 'Logs'
New-Item -ItemType Directory -Path $root,$logDir -Force | Out-Null
$logPath = Join-Path $logDir ('Setup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
Start-Transcript -Path $logPath | Out-Null
$workDir = Join-Path $env:TEMP ('WindowsSetup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
$results = [Collections.Generic.List[object]]::new()
function Step([string]$name, [scriptblock]$do) {
    Write-Host "`n>> $name" -ForegroundColor Cyan
    $script:stepResult = 'Applied'
    $script:stepNotes = 'See log'
    try {
        & $do
        $results.Add([pscustomobject]@{Step=$name;Result=$script:stepResult;Notes=$script:stepNotes})
        $colour = if ($script:stepResult -eq 'Applied') { 'Green' } else { 'Yellow' }
        Write-Host "$($script:stepResult) (check results and UI after sign-in)" -ForegroundColor $colour
    }
    catch { $results.Add([pscustomobject]@{Step=$name;Result='FAILED';Notes=$_.Exception.Message}); Write-Warning "$name : $($_.Exception.Message)" }
}
function DownloadSigned([string]$url,[string]$to,[string]$publisherRegex) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $to -UseBasicParsing -MaximumRedirection 5
    $sig = Get-AuthenticodeSignature -FilePath $to
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch $publisherRegex) {
        throw "Unexpected or invalid vendor signature for $to ($($sig.Status), $($sig.SignerCertificate.Subject))"
    }
}
function MustExitZero([string]$exe,[string[]]$arguments,[int[]]$allowed=@(0)) {
    $p = Start-Process -FilePath $exe -ArgumentList $arguments -Wait -PassThru
    if ($p.ExitCode -notin $allowed) { throw "$exe exited with $($p.ExitCode)" }
}
try {
    Write-Host "Windows VPS Setup | $($os.Caption) ($($os.BuildNumber)) | $env:USERNAME" -ForegroundColor Cyan
    Step '1. Chrome Stable (English)' {
        $file = Join-Path $workDir 'chrome.msi'
        DownloadSigned 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi' $file 'Google'
        MustExitZero 'msiexec.exe' @('/i',"`"$file`"",'/qn','/norestart') @(0,3010)
        if (-not (Test-Path "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe")) { throw 'Chrome executable not found' }
    }
    Step '2. WinRAR Stable (English), optional local licence' {
        $html = (Invoke-WebRequest 'https://www.rarlab.com/download.htm' -UseBasicParsing).Content
        $start = $html.IndexOf('English WinRAR and RAR release', [StringComparison]::OrdinalIgnoreCase)
        if ($start -lt 0) { throw 'Could not identify stable WinRAR section; refusing beta download' }
        $stableSection = $html.Substring($start, [Math]::Min(15000, $html.Length - $start))
        $m = [regex]::Match($stableSection,'(?i)(?:https?://(?:www\.)?rarlab\.com/)?rar/winrar-x64-(\d{3,4})\.exe')
        if (-not $m.Success) { throw 'Could not extract English stable x64 WinRAR link; site markup changed' }
        $file = Join-Path $workDir 'winrar.exe'
        DownloadSigned "https://www.rarlab.com/rar/winrar-x64-$($m.Groups[1].Value).exe" $file 'win\.rar|RARLAB'
        MustExitZero $file @('/S')
        $dir = Join-Path $env:ProgramFiles 'WinRAR'
        if (-not (Test-Path (Join-Path $dir 'WinRAR.exe'))) { throw 'WinRAR executable not found' }
        if ($WinRARLicensePath) {
            Copy-Item -LiteralPath $WinRARLicensePath -Destination (Join-Path $dir 'rarreg.key') -Force
            if ((Get-FileHash -LiteralPath $WinRARLicensePath).Hash -ne (Get-FileHash -LiteralPath (Join-Path $dir 'rarreg.key')).Hash) {
                throw 'WinRAR licence copy verification failed'
            }
            Write-Host 'Local WinRAR licence copied and verified.'
        } else {
            Write-Host 'No local licence supplied. WinRAR installed; any existing licence is preserved.' -ForegroundColor Yellow
        }
    }
    Step '3. Internet Explorer Enhanced Security Configuration' {
        $script:stepResult = 'Not applicable'
        $script:stepNotes = 'Windows Server-only setting. No IE ESC registry changes on Windows 11.'
        Write-Host $script:stepNotes
    }
    Step '4. UK time zone' {
        Set-TimeZone -Id 'GMT Standard Time'
        if ((Get-TimeZone).Id -ne 'GMT Standard Time') { throw 'UK time zone was not applied' }
    }
    Step '5. Windows 11 system tray visibility' {
        $script:stepResult = 'Manual setting'
        $script:stepNotes = 'Windows 11 manages tray icons per app. Review Settings > Personalisation > Taskbar > Other system tray icons. No universal legacy show-all setting is claimed.'
        Write-Host $script:stepNotes -ForegroundColor Yellow
    }
    Step '6. Automatic fix for blurry applications (user preference)' {
        Dword 'HKCU:\Control Panel\Desktop' 'EnablePerProcessSystemDPI' 1
        Dword 'HKCU:\Control Panel\Desktop' 'DisableAutomaticDpiScaling' 0
    }
    Step '7. High Performance power plan' {
        $guid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        $plans = (powercfg.exe /L | Out-String)
        if ($plans -notmatch [regex]::Escape($guid)) {
            $created = (powercfg.exe /duplicatescheme $guid | Out-String)
            if ($LASTEXITCODE -ne 0) { throw "Failed to duplicate High Performance plan: $created" }
            $match = [regex]::Match($created,'[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}')
            if (-not $match.Success) { throw 'New power scheme identifier missing' }
            $guid = $match.Value
        }
        powercfg.exe /S $guid
        if ($LASTEXITCODE -ne 0) { throw 'Could not activate High Performance power plan' }
    }
    Step '8. Never turn off display or sleep (AC/DC)' {
        foreach ($arg in @('monitor-timeout-ac','monitor-timeout-dc','standby-timeout-ac','standby-timeout-dc')) {
            powercfg.exe /change $arg 0
            if ($LASTEXITCODE -ne 0) { throw "powercfg failed: $arg" }
        }
    }
    Step '9. Windows 11 Start recent-app and Jump List preferences' {
        $advanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Dword $advanced 'Start_TrackDocs' 0
        Dword $advanced 'Start_TrackProgs' 0
        Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowRecent' 0
        Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowFrequent' 0
        # Enforce no Recently added section after sign-in. The Settings control becomes greyed out.
        Dword 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'HideRecentlyAddedApps' 1
    }
    Step '10. Windows 11 Start pins and Chrome taskbar layout' {
        $state = Set-Windows11ShellLayout -Root $root -SourceDirectory $PSScriptRoot -BuildNumber ([int]$os.BuildNumber)
        $script:stepResult = $state.Status
        $script:stepNotes = $state.Notes
        Write-Host $state.Notes -ForegroundColor Yellow
    }
    Step '11-12. Chrome in layout; taskbar order and Edge cleanup are manual' {
        # The layout policy above includes Chrome. Windows may retain existing user pins,
        # so never claim that Chrome is first or that Edge is removed automatically.
        $script:stepResult = 'Manual setting'
        $script:stepNotes = 'Review Chrome pinning/order and unpin Edge after sign-in. Windows can preserve existing user pins.'
        Write-Host $script:stepNotes -ForegroundColor Yellow
    }
    Step '13. Network discovery and file/printer sharing for active network profiles' {
        Enable-VpsNetworkSharing
    }
    Step '14. Disable app and toast notifications' {
        Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 0
        Dword 'HKCU:\Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications' 'NoToastApplicationNotification' 1
        Dword 'HKCU:\Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications' 'NoToastApplicationNotificationOnLockScreen' 1
        Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0
        Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 0
    }
    Step '15. Chrome default browser' {
        $state = Set-VpsChromeDefaults -Root $root
        $script:stepResult = $state.Status
        $script:stepNotes = $state.Notes
        Write-Host $state.Notes -ForegroundColor Yellow
    }
    Step '16. Disable optional consumer startup services' {
        Disable-VpsOptionalServices -Root $root
    }
    Step '17. Daily Storage Sense and Windows update/temp cleanup' {
        $state = Enable-VpsStorageCleanup -Root $root -SourceDirectory $PSScriptRoot
        if (-not $state.StorageSenseAvailable) {
            $script:stepResult = 'Fallback configured'
            $script:stepNotes = 'Storage Sense unavailable; daily Windows Disk Cleanup configured.'
        } else {
            $script:stepNotes = 'Daily Storage Sense enabled; Windows cleanup task at 03:30 local time.'
        }
    }
    Write-Host "`n=== SETUP RESULTS ===" -ForegroundColor Cyan
    $results | Format-Table -AutoSize
    $failed = @($results | Where-Object { $_.Result -eq 'FAILED' })
    if ($failed.Count -gt 0) {
        Write-Host "`nFAILURE DETAILS" -ForegroundColor Red
        $failed | Format-List -Property @('Step','Notes')
    }
    Write-Host "Log: $logPath"
    Write-Host 'Sign out and sign in for Start policy to apply; some settings require reboot.' -ForegroundColor Yellow
    Write-Host 'The taskbar icon order / unpinning Edge remain manual.' -ForegroundColor Yellow
    Write-Host 'Sharing includes active Public profiles; existing rule address/port/endpoint filters are preserved.' -ForegroundColor Yellow
    if (@($results | Where-Object { $_.Step -like '15.*' -and $_.Result -eq 'Needs action' }).Count -gt 0) {
        Write-Host 'ACTION: In Settings > Apps > Default apps, select Google Chrome and choose Set default.' -ForegroundColor Yellow
    }
    $results | Export-Csv -LiteralPath (Join-Path $logDir ('Results-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.csv')) -NoTypeInformation
    if (@($results | Where-Object { $_.Result -eq 'FAILED' }).Count -gt 0) {
        throw 'One or more setup steps failed. Review the results and log above.'
    }
} finally {
    Stop-Transcript | Out-Null
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
}
