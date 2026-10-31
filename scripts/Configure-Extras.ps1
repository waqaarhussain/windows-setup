#Requires -Version 5.1
# Functions only. Dot-source from setup or from the non-destructive validation script.
function Ensure-SetupRegistryKey([string]$Path) {
    $match = [regex]::Match($Path, '^(HKCU|HKLM):\\(.+)$', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { throw 'Registry helpers support literal HKCU or HKLM paths only.' }
    $hive = if ($match.Groups[1].Value -ieq 'HKCU') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine }
    # CreateSubKey opens existing keys without replacing values or child keys.
    $key = $hive.CreateSubKey($match.Groups[2].Value)
    if (-not $key) { throw "Could not open or create registry key: $Path" }
    $key.Dispose()
}

function Dword([string]$Path, [string]$Name, [int]$Value) {
    Ensure-SetupRegistryKey -Path $Path
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    if ((Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name -ne $Value) {
        throw "Registry value verification failed: $Path / $Name"
    }
}

function Get-VpsFirewallProfileNames([object[]]$Connections) {
    @($Connections | ForEach-Object {
        switch ($_.NetworkCategory.ToString()) {
            'DomainAuthenticated' { 'Domain' }
            'Private' { 'Private' }
            'Public' { 'Public' }
            default { throw "Unknown active network category: $($_.NetworkCategory)" }
        }
    } | Select-Object -Unique)
}

function Enable-VpsNetworkSharing {
    $connections = @(Get-NetConnectionProfile | Where-Object {
        $_.IPv4Connectivity -ne 'Disconnected' -or $_.IPv6Connectivity -ne 'Disconnected'
    })
    if ($connections.Count -eq 0) { throw 'No active network profile found.' }
    $profileNames = @(Get-VpsFirewallProfileNames -Connections $connections)
    foreach ($name in @('fdPHost','FDResPub','SSDPSRV','upnphost','LanmanServer')) {
        Set-Service -Name $name -StartupType Automatic
        Start-Service -Name $name -ErrorAction Stop
    }
    foreach ($connection in $connections) {
        Write-Host "Configuring discovery/sharing: $($connection.InterfaceAlias) ($($connection.NetworkCategory))"
    }
    foreach ($group in @('Network Discovery','File and Printer Sharing')) {
        $rules = @(Get-NetFirewallRule -DisplayGroup $group -ErrorAction Stop)
        if ($rules.Count -eq 0) { throw "Missing firewall rule group: $group" }
        # Scope inbound rules before enabling them. Preserve native multicast/outbound scopes.
        $rules | Where-Object { $_.Direction -eq 'Inbound' } | Set-NetFirewallRule -RemoteAddress LocalSubnet -ErrorAction Stop
        $rules | Set-NetFirewallRule -Enabled True -Profile $profileNames -ErrorAction Stop
        $effective = @(Get-NetFirewallRule -PolicyStore ActiveStore -DisplayGroup $group -ErrorAction Stop)
        foreach ($profileName in $profileNames) {
            foreach ($rule in $rules) {
                $matching = @($effective | Where-Object {
                    $_.Name -eq $rule.Name -and $_.Enabled -eq 'True' -and
                    ($_.Profile.ToString() -match "(^|,\s*)$profileName($|,)|^Any$")
                })
                if ($matching.Count -eq 0) { throw "Rule $($rule.Name) is not effectively enabled for $profileName; check Group Policy." }
            }
        }
    }
    Write-Host "Discovery and sharing enabled for: $($profileNames -join ', '). Inbound rules are scoped to LocalSubnet." -ForegroundColor Green
}

function Get-VpsOptionalServiceNames {
    @('Fax','MapsBroker','RetailDemo','WMPNetworkSvc','XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc')
}

function Get-VpsCleanupHandlers {
    @('Update Cleanup','Temporary Files','Temporary Setup Files','Delivery Optimization Files')
}

function Update-ChromeAssociationDocument([xml]$Document) {
    if (-not $Document.DocumentElement -or $Document.DocumentElement.Name -ne 'DefaultAssociations') {
        throw 'Unexpected default-associations XML root.'
    }
    foreach ($identifier in @('.htm','.html','http','https')) {
        $nodes = @($Document.DocumentElement.SelectNodes("Association[@Identifier='$identifier']"))
        if ($nodes.Count -eq 0) {
            $node = $Document.CreateElement('Association')
            [void]$Document.DocumentElement.AppendChild($node)
        } else {
            $node = $nodes[0]
            foreach ($duplicate in @($nodes | Select-Object -Skip 1)) {
                [void]$Document.DocumentElement.RemoveChild($duplicate)
            }
        }
        $node.SetAttribute('Identifier', $identifier)
        $node.SetAttribute('ProgId', 'ChromeHTML')
        $node.SetAttribute('ApplicationName', 'Google Chrome')
    }
    return ,$Document
}

function Set-VpsChromeDefaults([string]$Root) {
    if (-not (Test-Path 'Registry::HKEY_CLASSES_ROOT\ChromeHTML')) { throw 'ChromeHTML is not registered. Check Chrome installation.' }
    $export = Join-Path $Root 'CurrentDefaultAssociations.xml'
    & dism.exe /Online "/Export-DefaultAppAssociations:$export" /Quiet | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Could not export existing default app associations.' }
    $backup = Join-Path $Root 'DefaultAssociations-before-setup.xml'
    if (-not (Test-Path $backup)) { Copy-Item -LiteralPath $export -Destination $backup }
    [xml]$document = Get-Content -LiteralPath $export -Raw
    $document = Update-ChromeAssociationDocument $document
    $defaults = Join-Path $Root 'ChromeDefaults.xml'
    $document.Save($defaults)
    & dism.exe /Online "/Import-DefaultAppAssociations:$defaults" /Quiet | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Could not import Chrome defaults for new user profiles.' }

    $joined = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
    if ($joined) {
        $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
        $existing = (Get-ItemProperty -Path $policy -Name DefaultAssociationsConfiguration -ErrorAction SilentlyContinue).DefaultAssociationsConfiguration
        if ($existing -and $existing -ne $defaults) {
            Write-Warning 'An existing default-associations policy is configured. It was preserved; it may override Chrome at sign-in.'
        } else {
            Ensure-SetupRegistryKey -Path $policy
            New-ItemProperty -Path $policy -Name DefaultAssociationsConfiguration -Value $defaults -PropertyType String -Force | Out-Null
        }
    }
    $choices = @(
        'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice',
        'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice'
    )
    $current = @($choices | ForEach-Object {
        (Get-ItemProperty -Path $_ -Name ProgId -ErrorAction SilentlyContinue).ProgId
    })
    if ($current.Count -eq 2 -and @($current | Where-Object { $_ -ne 'ChromeHTML' }).Count -eq 0) {
        return [pscustomobject]@{ Status='Applied'; Notes='Current HTTP/HTTPS choices are Chrome; new-profile defaults imported.' }
    }
    Start-Process 'ms-settings:defaultapps'
    return [pscustomobject]@{ Status='Needs action'; Notes='In Settings > Apps > Default apps, select Google Chrome and choose Set default. New-profile defaults imported; existing user choice requires confirmation.' }
}

function Disable-VpsOptionalServices([string]$Root) {
    $backupPath = Join-Path $Root 'OptionalServices-before-setup.json'
    $backup = @()
    if (Test-Path $backupPath) { $backup = @(Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json) }
    $changed = 0
    foreach ($name in Get-VpsOptionalServiceNames) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $service) { Write-Host "$name : not installed"; continue }
        if (@($service.DependentServices | Where-Object { $_.Status -eq 'Running' }).Count -gt 0) {
            Write-Warning "$name has running dependent services; skipped."
            continue
        }
        if (@($backup | Where-Object { $_.Name -eq $name }).Count -eq 0) {
            $key = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
            $backup += [pscustomobject]@{ Name=$name; Start=[int]$key.Start; DelayedAutoStart=[int]$key.DelayedAutoStart; WasRunning=($service.Status -eq 'Running') }
            ConvertTo-Json -InputObject $backup -Depth 3 | Set-Content -LiteralPath $backupPath -Encoding UTF8
        }
        if ($service.Status -ne 'Stopped') { Stop-Service -Name $name -ErrorAction Stop }
        if ($service.StartType -ne 'Disabled') { Set-Service -Name $name -StartupType Disabled; $changed++ }
        $verified = Get-Service -Name $name
        if ($verified.Status -ne 'Stopped' -or $verified.StartType -ne 'Disabled') { throw "Could not disable $name" }
        Write-Host "$name : disabled"
    }
    Write-Host "Changed startup type for $changed optional services. Original states: $backupPath"
}

function Enable-VpsStorageCleanup([string]$Root, [string]$SourceDirectory) {
    $maintenance = Join-Path $Root 'Maintenance'
    New-Item -ItemType Directory -Path $maintenance -Force | Out-Null
    & icacls.exe $maintenance /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Could not protect the SYSTEM cleanup script directory.' }
    $worker = Join-Path $maintenance 'Invoke-StorageCleanup.ps1'
    Copy-Item -LiteralPath (Join-Path $SourceDirectory 'Invoke-StorageCleanup.ps1') -Destination $worker -Force

    $storageService = Get-Service -Name StorSvc -ErrorAction SilentlyContinue
    $storageTask = @(Get-ScheduledTask -TaskPath '\Microsoft\Windows\DiskFootprint\' -TaskName StorageSense -ErrorAction SilentlyContinue)
    $storageAvailable = [bool]($storageService -and $storageTask.Count -gt 0)
    if ($storageAvailable) {
        $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense'
        $values = @{
            AllowStorageSenseGlobal=1
            AllowStorageSenseTemporaryFilesCleanup=1
            ConfigStorageSenseGlobalCadence=1
            ConfigStorageSenseDownloadsCleanupThreshold=0
            ConfigStorageSenseRecycleBinCleanupThreshold=0
            ConfigStorageSenseCloudContentDehydrationThreshold=0
        }
        Ensure-SetupRegistryKey -Path $policy
        foreach ($entry in $values.GetEnumerator()) {
            New-ItemProperty -Path $policy -Name $entry.Key -Value $entry.Value -PropertyType DWord -Force | Out-Null
            if ((Get-ItemProperty -Path $policy -Name $entry.Key).($entry.Key) -ne $entry.Value) { throw 'Storage Sense policy verification failed.' }
        }
        if ($storageService.StartType -eq 'Disabled') { Set-Service -Name StorSvc -StartupType Manual }
        $storageTask | Enable-ScheduledTask | Out-Null
        Write-Host 'Storage Sense enabled daily for unused temporary files. Downloads, Recycle Bin and cloud files excluded.'
    } else {
        Write-Warning 'Storage Sense service/task unavailable on this image. Scheduled Windows Disk Cleanup is configured instead; no Storage Sense success is claimed.'
    }

    if (-not (Test-Path "$env:windir\System32\cleanmgr.exe")) { throw 'Windows Disk Cleanup is unavailable.' }
    $cacheRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $handlers = @(Get-ChildItem -LiteralPath $cacheRoot)
    $selected = 0
    foreach ($handler in $handlers) {
        $enabled = if ($handler.PSChildName -in @(Get-VpsCleanupHandlers)) { 2 } else { 0 }
        New-ItemProperty -LiteralPath $handler.PSPath -Name StateFlags2072 -Value $enabled -PropertyType DWord -Force | Out-Null
        if ($enabled -eq 2) { $selected++ }
    }
    if ($selected -eq 0) { throw 'No supported Windows cleanup handlers were found.' }
    $action = New-ScheduledTaskAction -Execute "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$worker`""
    $trigger = New-ScheduledTaskTrigger -Daily -At '03:30'
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 3)
    Register-ScheduledTask -TaskName 'WindowsSetup-StorageCleanup' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Windows-managed cleanup of eligible update remnants and temporary files; skips busy servicing and pending restarts.' -Force | Out-Null
    $task = Get-ScheduledTask -TaskName 'WindowsSetup-StorageCleanup'
    if ($task.State -eq 'Disabled') { throw 'Daily storage cleanup task is disabled.' }
    Write-Host "Daily Windows cleanup scheduled at 03:30 local time with $selected supported handlers. No cleanup is run during setup."
    return [pscustomobject]@{ StorageSenseAvailable=$storageAvailable; CleanupHandlers=$selected }
}
