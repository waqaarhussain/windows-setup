#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Configure-Extras.ps1')

# Merging browser defaults must preserve unrelated file associations and remove duplicates.
[xml]$sample = '<DefaultAssociations><Association Identifier=".pdf" ProgId="ExistingPDF" ApplicationName="PDF app"/><Association Identifier="https" ProgId="OldBrowser"/><Association Identifier="https" ProgId="DuplicateBrowser"/></DefaultAssociations>'
$merged = Update-ChromeAssociationDocument $sample
foreach ($identifier in @('.htm','.html','http','https')) {
    $matches = @($merged.DocumentElement.SelectNodes("Association[@Identifier='$identifier']"))
    if ($matches.Count -ne 1 -or $matches[0].GetAttribute('ProgId') -ne 'ChromeHTML') { throw "Invalid browser mapping: $identifier" }
}
if ($merged.SelectSingleNode("/DefaultAssociations/Association[@Identifier='.pdf']").GetAttribute('ProgId') -ne 'ExistingPDF') {
    throw 'An unrelated file association was changed.'
}
$beforeRepeat = $merged.OuterXml
$again = Update-ChromeAssociationDocument $merged
if ($again.OuterXml -ne $beforeRepeat) { throw 'Browser association merge is not idempotent.' }
$invalidRejected = $false
try { Update-ChromeAssociationDocument ([xml]'<Unexpected/>') | Out-Null } catch { $invalidRejected = $true }
if (-not $invalidRejected) { throw 'Unexpected XML was accepted.' }

# Prevent future edits from sweeping essential services or user content into cleanup.
$protected = @('TermService','RpcSs','Winmgmt','Dhcp','Dnscache','MpsSvc','WinDefend','wuauserv','BITS','UsoSvc','TrustedInstaller','Spooler','LanmanServer','fdPHost','FDResPub','SSDPSRV','upnphost','StorSvc','WSearch','SysMain')
if (@(Get-VpsOptionalServiceNames | Where-Object { $_ -in $protected }).Count) { throw 'Essential service entered the optional-service list.' }
$expectedHandlers = @('Update Cleanup','Temporary Files','Temporary Setup Files','Delivery Optimization Files')
if (Compare-Object $expectedHandlers @(Get-VpsCleanupHandlers)) { throw 'Cleanup handler scope changed; review data-loss implications.' }
Write-Host 'PASS: Chrome XML merge/preservation, idempotence, invalid input, service exclusions, cleanup scope.'
