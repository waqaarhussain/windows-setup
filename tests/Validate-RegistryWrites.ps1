#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Configure-Extras.ps1')
# Only an isolated disposable test key is modified. Never touch actual Explorer/policy keys.
$testKey = 'HKCU:\Software\WindowsSetup.Tests\' + [guid]::NewGuid().ToString('N')
try {
    Ensure-SetupRegistryKey $testKey
    New-ItemProperty -LiteralPath $testKey -Name ExistingString -Value 'keep me' -PropertyType String | Out-Null
    Ensure-SetupRegistryKey "$testKey\Child\Grandchild"
    Dword "$testKey\Child\Grandchild" 'ExistingChildValue' 42

    # This sequence previously recreated the parent key on every write.
    Dword $testKey 'FirstSetting' 1
    Dword $testKey 'SecondSetting' 2
    Dword $testKey 'FirstSetting' 3
    Ensure-SetupRegistryKey $testKey
    $values = Get-ItemProperty -LiteralPath $testKey
    if ($values.ExistingString -ne 'keep me' -or $values.FirstSetting -ne 3 -or $values.SecondSetting -ne 2) {
        throw 'Repeated registry writes destroyed an existing or sibling value.'
    }
    if ((Get-ItemProperty -LiteralPath "$testKey\Child\Grandchild").ExistingChildValue -ne 42) {
        throw 'Repeated registry writes destroyed a child key.'
    }
    $key = Get-Item -LiteralPath $testKey
    if ($key.GetValueKind('FirstSetting') -ne [Microsoft.Win32.RegistryValueKind]::DWord) { throw 'Wrong registry value type.' }
    Write-Host 'PASS: existing values, sibling settings and child keys survive repeated writes.'
} finally {
    if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force }
}
