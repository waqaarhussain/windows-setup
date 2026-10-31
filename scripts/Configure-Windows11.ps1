#Requires -Version 5.1
# Functions only, so capability checks can be tested without changing Windows.
function Test-Windows11Target([int]$BuildNumber, [int]$ProductType, [string]$Architecture) {
    return ($ProductType -eq 1 -and $BuildNumber -ge 22000 -and $Architecture -eq 'AMD64')
}

function Test-Windows11StartPinsSupport([int]$BuildNumber, [string]$EditionId, [bool]$HasPolicyTemplate) {
    return ($BuildNumber -ge 26100 -and $EditionId -notlike 'Core*' -and $HasPolicyTemplate)
}

function Set-Windows11ShellLayout([string]$Root, [string]$SourceDirectory, [int]$BuildNumber) {
    $chrome = Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'
    if (-not (Test-Path $chrome)) { throw 'Chrome is required for the taskbar layout.' }
    $shortcutPath = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $chrome
    $shortcut.Save()

    $policy = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
    $backup = Join-Path $Root 'ExplorerPolicy-before-setup.reg'
    if ((Test-Path $policy) -and -not (Test-Path $backup)) {
        & reg.exe export 'HKCU\Software\Policies\Microsoft\Windows\Explorer' $backup /y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not back up existing Explorer policy.' }
    }
    $assets = Join-Path (Split-Path $SourceDirectory) 'assets'
    $taskbar = Join-Path $Root 'TaskbarLayout.xml'
    Copy-Item -LiteralPath (Join-Path $assets 'TaskbarLayout.xml') -Destination $taskbar -Force
    [xml]$validatedTaskbar = Get-Content -LiteralPath $taskbar -Raw
    New-Item -Path $policy -Force | Out-Null
    New-ItemProperty -Path $policy -Name StartLayoutFile -Value $taskbar -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $policy -Name LockedStartLayout -Value 1 -PropertyType DWord -Force | Out-Null

    $hasPolicy = $false
    $admx = Join-Path $env:windir 'PolicyDefinitions\StartMenu.admx'
    if (Test-Path $admx) {
        [xml]$template = Get-Content -LiteralPath $admx -Raw
        $hasPolicy = $null -ne $template.SelectSingleNode("//*[local-name()='policy' and @name='ConfigureStartPins']")
    }
    $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
    if (Test-Windows11StartPinsSupport -BuildNumber $BuildNumber -EditionId $edition -HasPolicyTemplate $hasPolicy) {
        $pins = Join-Path $Root 'StartPins.json'
        Copy-Item -LiteralPath (Join-Path $assets 'StartPins.json') -Destination $pins -Force
        $validatedPins = Get-Content -LiteralPath $pins -Raw | ConvertFrom-Json
        New-ItemProperty -Path $policy -Name ConfigureStartPins -Value $pins -PropertyType String -Force | Out-Null
        return [pscustomobject]@{ Status='Sign-in required'; Notes='Windows 11 empty Start pins and Chrome taskbar policy configured. Sign out and in; existing taskbar order may remain.' }
    }
    return [pscustomobject]@{ Status='Manual setting'; Notes='Chrome taskbar policy configured. This image lacks the supported Windows 11 Start-pins GPO; remove Start pins manually or update Windows. All apps remains available.' }
}
