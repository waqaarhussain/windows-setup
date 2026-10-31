#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
# Load only the validator function. Never execute the installer during CI.
$tokens = $null
$errors = $null
$source = Join-Path $PSScriptRoot '..\install.ps1'
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Installer syntax errors.' }
$function = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-WinRARLicenseFile' }, $true)
if (-not $function) { throw 'Licence validator missing.' }
. ([scriptblock]::Create($function.Extent.Text))

$temporary = Join-Path $env:TEMP ('WinRARLicenseTest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $candidate = Join-Path $temporary 'candidate.key'
    Set-Content -LiteralPath $candidate -Value '<html><body>Sign in to Google Drive</body></html>'
    if (Test-WinRARLicenseFile $candidate) { throw 'HTML download was accepted as a licence.' }
    Set-Content -LiteralPath $candidate -Value "RAR registration data`r`nCI dummy fixture`r`nUID=TEST-ONLY`r`nnot-a-real-licence"
    if (-not (Test-WinRARLicenseFile $candidate)) { throw 'Registration-format fixture was rejected.' }
    Set-Content -LiteralPath $candidate -Value 'RAR registration data'
    if (Test-WinRARLicenseFile $candidate) { throw 'Truncated download was accepted.' }
    if (Test-WinRARLicenseFile (Join-Path $temporary 'missing.key')) { throw 'Missing download was accepted.' }
    Write-Host 'PASS: licence-format fixture accepted; HTML, truncated and missing downloads rejected. No real licence downloaded.'
} finally { Remove-Item -LiteralPath $temporary -Recurse -Force }
