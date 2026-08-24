[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $repositoryRoot 'install.ps1'
$readmePath = Join-Path $repositoryRoot 'README.md'

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $installerPath,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null

if ($parseErrors.Count -gt 0) {
    $messages = $parseErrors | ForEach-Object { $_.Message }
    throw "install.ps1 has syntax errors:`n$($messages -join "`n")"
}

$installer = Get-Content -Raw -LiteralPath $installerPath
$readme = Get-Content -Raw -LiteralPath $readmePath

$requiredInstallerText = @(
    'clay-run/agent-plugins',
    '/usr/local/bin/clay-windows',
    'ClayCLI',
    'Existing clay command found',
    'Get-Command clay -All',
    '$Directory + $otherEntries'
)

foreach ($required in $requiredInstallerText) {
    if (-not $installer.Contains($required)) {
        throw "install.ps1 is missing required text: $required"
    }
}

if (-not $readme.Contains('irm https://raw.githubusercontent.com/danielkupka/clay-cli-windows/v0.2.0/install.ps1 | iex')) {
    throw 'README.md is missing the pinned one-line installer.'
}

$match = [regex]::Match(
    $installer,
    '(?s)# BEGIN_WSL_FORWARDER.*?\$template = @''\r?\n(?<script>.*?)\r?\n''@.*?# END_WSL_FORWARDER'
)
if (-not $match.Success) {
    throw 'Could not extract the embedded WSL forwarder for validation.'
}

$forwarder = $match.Groups['script'].Value
if (-not $forwarder.StartsWith('#!/bin/sh')) {
    throw 'The embedded WSL forwarder has no POSIX shell shebang.'
}
if (-not $forwarder.Contains('exec "$normalized_bin/clay" "$@"')) {
    throw 'The embedded WSL forwarder does not preserve CLI arguments.'
}

Write-Host 'Installer syntax and required-content checks passed.' -ForegroundColor Green
