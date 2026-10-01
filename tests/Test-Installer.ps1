[CmdletBinding()]
param([string]$ExportScripts, [string]$FixtureExecutable = "/tmp/clay test/user's cli")

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $repositoryRoot 'install.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors.Message -join "`n") }
# Load only function definitions, never execute the installer or change real PATH.
foreach ($function in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($function.Extent.Text))
}
function Assert-Equal($Actual, $Expected, $Name) {
    if ($Actual -cne $Expected) { throw "$Name expected [$Expected], got [$Actual]" }
}
Assert-Equal (Get-BridgePath 'C:\old;C:\tools' 'C:\bridge') 'C:\bridge;C:\old;C:\tools' 'PATH order'
Assert-Equal (Get-BridgePath 'C:\old;C:\BRIDGE\;C:\tools;C:\bridge' 'C:\bridge') 'C:\bridge;C:\old;C:\tools' 'PATH deduplication'
Assert-Equal (Get-BridgePath '' 'C:\bridge') 'C:\bridge' 'Empty PATH'
$first = Get-BridgePath 'C:\old;C:\tools' 'C:\bridge'
Assert-Equal (Get-BridgePath $first 'C:\bridge') $first 'Idempotent PATH'
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    Assert-Equal (ConvertTo-WslPath 'C:\Folder With Spaces\clay') '/mnt/c/Folder With Spaces/clay' 'Path mapping'
}
$forwarder = Get-ForwarderScript '/home/user/.local/bin/clay'
if (-not $forwarder.Contains('"$@"')) { throw 'Forwarder lost argument quoting' }
if ($forwarder.Contains("`r")) { throw 'Forwarder contains CRLF' }
$rejected = $false
try { Get-ForwarderScript "relative`npath" | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Invalid executable accepted' }

if ($ExportScripts) {
    New-Item -ItemType Directory -Path $ExportScripts -Force | Out-Null
    Write-LfFile (Join-Path $ExportScripts 'bootstrap.sh') (Get-BootstrapScript)
    Write-LfFile (Join-Path $ExportScripts 'migrate.sh') (Get-MigrationScript)
    Write-LfFile (Join-Path $ExportScripts 'forwarder.sh') $forwarder
    Write-LfFile (Join-Path $ExportScripts 'quoted-forwarder.sh') (Get-ForwarderScript $FixtureExecutable)
}
Write-Host 'Installer syntax, PATH behavior, and forwarder checks passed.'
