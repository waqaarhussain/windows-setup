#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
function Invoke-VpsStorageCleanup {
    $logRoot = Join-Path $env:ProgramData 'WindowsSetup\Logs'
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    Start-Transcript -Path (Join-Path $logRoot ('Cleanup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')) | Out-Null
    try {
        $pending = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        )
        if (@($pending | Where-Object { Test-Path $_ }).Count -gt 0) {
            Write-Host 'Cleanup deferred: Windows servicing needs a restart.'
            return
        }
        $busy = @(Get-Process -Name @('TiWorker','dism','cleanmgr','setuphost') -ErrorAction SilentlyContinue)
        if ($busy.Count -gt 0) { Write-Host 'Cleanup deferred: servicing/cleanup is already running.'; return }
        # If update state cannot be read, fail closed and let the next daily run retry.
        $installer = New-Object -ComObject Microsoft.Update.Installer
        try {
            if ($installer.IsBusy) { Write-Host 'Cleanup deferred: Windows Update is installing.'; return }
        } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer) }
        $process = Start-Process -FilePath "$env:windir\System32\cleanmgr.exe" -ArgumentList '/sagerun:2072' -PassThru -Wait
        if ($process.ExitCode -ne 0) { throw "Windows Disk Cleanup exited with $($process.ExitCode)" }
        $componentTask = Get-ScheduledTask -TaskPath '\Microsoft\Windows\Servicing\' -TaskName StartComponentCleanup -ErrorAction SilentlyContinue
        if ($componentTask -and $componentTask.State -eq 'Ready') {
            Start-ScheduledTask -InputObject $componentTask
            Write-Host 'Windows component cleanup task started. Completion is tracked by Task Scheduler.'
        }
        Write-Host 'Windows Disk Cleanup finished. Windows decides which update files are eligible.'
    } finally { Stop-Transcript | Out-Null }
}
if ($MyInvocation.InvocationName -ne '.') { Invoke-VpsStorageCleanup }
