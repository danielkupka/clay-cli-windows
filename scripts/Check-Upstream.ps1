[CmdletBinding()]
param([switch]$RefreshBaseline)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$baselinePath = Join-Path $PSScriptRoot 'upstream-baseline.json'
function Get-GitHubJson([string]$Endpoint) {
    $result = & gh api $Endpoint
    if ($LASTEXITCODE -ne 0) { throw "GitHub request failed: $Endpoint" }
    return ($result -join "`n" | ConvertFrom-Json -AsHashtable)
}

# Read metadata only. Never run code from the upstream repository.
$commit = Get-GitHubJson 'repos/clay-run/agent-plugins/commits/main'
$tree = Get-GitHubJson "repos/clay-run/agent-plugins/git/trees/$($commit.sha)?recursive=1"
if ($tree.truncated) { throw 'Upstream file listing was truncated; cannot establish a complete baseline.' }
$files = [ordered]@{}
foreach ($entry in $tree.tree | Sort-Object path) {
    if ($entry.type -eq 'blob' -and $entry.path -match '(^GETTING_STARTED\.md$|^README\.md$|^clay/(scripts/|skills/(setup|update|cli)/|cli-min-version$|\.claude-plugin/plugin\.json$))') {
        $files[$entry.path] = $entry.sha
    }
}
$releases = @(Get-GitHubJson 'repos/clay-run/agent-plugins/releases?per_page=100')
$stable = @($releases | Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -match '^clay-cli-v\d+\.\d+\.\d+$' } | Sort-Object { [version]($_.tag_name -replace '^clay-cli-v', '') } -Descending)
if (-not $stable.Count) { throw 'No official stable CLI release found.' }
$snapshot = [ordered]@{ reviewedCommit = $commit.sha; cliRelease = $stable[0].tag_name; files = $files }
if ($RefreshBaseline) {
    $snapshot | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $baselinePath -Encoding utf8
    Write-Output 'Baseline refreshed. Review the upstream diff before committing this file.'
    return
}
$baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json -AsHashtable
$findings = [Collections.Generic.List[string]]::new()
foreach ($path in @(@($baseline.files.Keys) + @($files.Keys) | Sort-Object -Unique)) {
    if ($baseline.files[$path] -ne $files[$path]) { $findings.Add("Upstream file changed: $path") }
}
if ($baseline.cliRelease -ne $snapshot.cliRelease) {
    $findings.Add("New stable CLI release: $($baseline.cliRelease) -> $($snapshot.cliRelease). Release notes: $($stable[0].html_url)")
}

# Check the exact advertised installer, including the tag, without executing it.
$readme = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw
$links = @([regex]::Matches($readme, 'https://raw\.githubusercontent\.com/danielkupka/clay-cli-windows/(v\d+\.\d+\.\d+)/install\.ps1') | ForEach-Object { $_.Value } | Sort-Object -Unique)
if ($links.Count -ne 1) { throw 'README must advertise exactly one pinned installer version.' }
$advertised = (Invoke-WebRequest -Uri $links[0]).Content -replace "`r`n", "`n"
$local = (Get-Content -LiteralPath (Join-Path $repoRoot 'install.ps1') -Raw) -replace "`r`n", "`n"
if ($advertised -cne $local) { $findings.Add('The advertised release installer differs from the current installer. Review whether a new release is required.') }

$summary = @(
    '## Daily Clay compatibility check',
    "Upstream comparison: https://github.com/clay-run/agent-plugins/compare/$($baseline.reviewedCommit)...$($commit.sha)",
    "Stable CLI: $($snapshot.cliRelease)",
    "Advertised installer: $($links[0])",
    'Windows tests cover PowerShell 5.1 first-run fixtures and Git Bash; Linux forwarding runs separately. Live Clay authentication and a real fresh WSL installation are not tested by GitHub.'
)
if ($findings.Count) {
    $summary += @('### Review required') + @($findings | ForEach-Object { "- $_" })
} else { $summary += 'No monitored upstream changes or unpublished installer differences detected.' }
$summary | Write-Output
if ($env:GITHUB_STEP_SUMMARY) { $summary | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY }
if ($findings.Count) { throw 'Compatibility review required. See the run summary; changes are not automatically classified as defects.' }
