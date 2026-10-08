[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$Distro = 'Ubuntu-24.04',
    [ValidateNotNullOrEmpty()]
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\ClayCLI'),
    [switch]$SkipLogin,
    [switch]$SkipPathUpdate,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Pin the installer code; the installed CLI can subsequently update independently.
$UpstreamRevision = 'ba5c72203c87ad2693017e59b7d0a362fe0e01a1'
$BaseMinimumVersion = [version]'1.4.0'

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function ConvertTo-WslPath {
    param([Parameter(Mandatory)][string]$WindowsPath)
    $fullPath = [IO.Path]::GetFullPath($WindowsPath)
    if ($fullPath -notmatch '^([A-Za-z]):\\(.*)$') {
        throw "Only local drive paths are supported: $fullPath"
    }
    return "/mnt/$($Matches[1].ToLowerInvariant())/$($Matches[2].Replace('\', '/'))"
}

function Get-BridgePath {
    param([AllowNull()][AllowEmptyString()][string]$CurrentPath, [string]$Directory)
    $others = @($CurrentPath -split ';' | Where-Object {
        $_ -and $_.Trim().Trim('"').TrimEnd('\') -ine $Directory.TrimEnd('\')
    })
    return (@($Directory) + $others) -join ';'
}

function Add-ToUserPath {
    param([string]$Directory)
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    [Environment]::SetEnvironmentVariable('Path', (Get-BridgePath $current $Directory), 'User')
    $env:Path = Get-BridgePath $env:Path $Directory
}

function Get-WslDistros {
    # Redirect native stderr in cmd, before PowerShell 5.1 can turn it into a
    # terminating NativeCommandError when the WSL stub reports "not installed".
    # /d disables cmd AutoRun; this command contains no interpolated user input.
    $names = & cmd.exe /d /c 'wsl.exe --list --quiet 2>nul'
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($names | ForEach-Object { ($_ -replace "\x00", '').Trim() } |
        Where-Object { $_ -and $_ -notlike 'docker-desktop*' })
}

function Install-WslIfNeeded {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'WSL is unavailable. Install WSL from Microsoft, restart Windows, and rerun this installer.'
    }
    $available = @(Get-WslDistros)
    if ($available -contains $Distro) { return $Distro }
    if ($available.Count -gt 0) {
        if ($script:ExplicitDistro) { throw "Requested WSL distribution $Distro is not installed." }
        return $available[0]
    }
    if ($DryRun) { return $Distro }
    Write-Step "Installing WSL and $Distro"
    $process = Start-Process wsl.exe -ArgumentList @('--install', '--distribution', $Distro, '--no-launch') -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) { throw "WSL installation failed: $($process.ExitCode)" }
    if ($process.ExitCode -eq 3010 -or @(Get-WslDistros) -notcontains $Distro) {
        throw 'Restart Windows, then rerun the same installer command.'
    }
    return $Distro
}

function Get-MinimumVersion {
    $minimum = $BaseMinimumVersion
    $roots = @(
        (Join-Path $env:USERPROFILE '.codex'),
        (Join-Path $env:USERPROFILE '.claude'),
        (Join-Path $env:USERPROFILE '.cursor')
    )
    if ($env:CODEX_HOME) { $roots += $env:CODEX_HOME }
    if ($env:CLAUDE_CONFIG_DIR) { $roots += $env:CLAUDE_CONFIG_DIR }
    $patterns = @($roots | ForEach-Object { Join-Path $_ 'plugins\cache\*\clay\*\cli-min-version' })
    $patterns += Join-Path $env:USERPROFILE '.cursor\plugins\local\clay\cli-min-version'
    $patterns += Join-Path $env:USERPROFILE '.config\clay-plugin\clay\cli-min-version'
    foreach ($pattern in $patterns) {
        foreach ($file in @(Get-Item -Path $pattern -ErrorAction SilentlyContinue)) {
            $value = (Get-Content -Raw -LiteralPath $file.FullName).Trim()
            if ($value -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid CLI minimum in $($file.FullName)" }
            if ([version]$value -gt $minimum) { $minimum = [version]$value }
        }
    }
    return $minimum.ToString()
}

function Write-LfFile {
    param([string]$Path, [string]$Content)
    [IO.File]::WriteAllText($Path, ($Content -replace "\r\n?", "`n"), [Text.UTF8Encoding]::new($false))
}

function Get-BootstrapScript {
    # BEGIN_WSL_BOOTSTRAP
    return @'
#!/usr/bin/env bash
set -euo pipefail
stage=$1
minimum=$2
source "$stage/cli-install-common.sh"
existing=$(command -v clay || true)
if [ -z "$existing" ] && { [ -e "$HOME/.local/bin/clay" ] || [ -L "$HOME/.local/bin/clay" ]; }; then
    existing="$HOME/.local/bin/clay"
fi
method=missing
[ -z "$existing" ] || method=$(clay_install_method "$existing")

# Keep a recoverable copy if upstream migrates this user's legacy forwarder.
if clay_is_legacy "$HOME/.local/bin/clay"; then
    backup=$(mktemp "$HOME/.local/bin/clay.legacy.XXXXXX")
    cp -p "$HOME/.local/bin/clay" "$backup"
    printf 'Legacy forwarder backup: %s\n' "$backup"
fi
bash "$stage/install-cli.sh" --version "$minimum"
case "$method" in
    native) target=$(clay_resolve_path "$existing") ;;
    npm|legacy-npm) target="$(npm prefix --global)/bin/clay" ;;
    *) target="$HOME/.local/bin/clay" ;;
esac
kind=$(clay_install_method "$target")
case "$kind" in native|npm) ;; *) printf 'Unverified CLI installation: %s\n' "$target" >&2; exit 1 ;; esac
version=$(clay_read_version "$target")
clay_version_at_least "$version" "$minimum" || { printf 'CLI below minimum\n' >&2; exit 1; }
target=$(clay_canonical_path "$target")
printf '%s\n' "$target" > "$stage/cli-path"
printf 'Verified independent Clay %s at %s\n' "$version" "$target"
'@
    # END_WSL_BOOTSTRAP
}

function Get-ForwarderScript {
    param([string]$Executable)
    if (-not $Executable.StartsWith('/') -or $Executable -match "[\r\n]") { throw 'Invalid Linux executable path.' }
    $quoted = "'" + $Executable.Replace("'", "'"+'"'+"'"+'"'+"'") + "'"
    return "#!/bin/sh`n# clay-cli-windows independent bridge v0.3.0`nexec $quoted `"$@`"" + "`n"
}

function Get-GitBashShimScript {
    param(
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')][string]$Distro,
        [ValidatePattern('^[a-zA-Z_][a-zA-Z0-9_-]*[$]?$')][string]$LinuxUser
    )
    # Literal template preserves "$@". Validated values are single-quoted so a
    # Linux account ending in $ is also forwarded literally.
    return @'
#!/bin/sh
# clay-cli-windows independent bridge (Git Bash shim)
export MSYS_NO_PATHCONV=1
exec wsl.exe -d '__DISTRO__' -u '__USER__' --exec /usr/local/bin/clay-windows "$@"
'@.Replace('__DISTRO__', $Distro).Replace('__USER__', $LinuxUser)
}

function Write-WindowsShims {
    param([string]$Directory, [string]$Distro, [string]$LinuxUser)
    $bashShim = Get-GitBashShimScript $Distro $LinuxUser
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    foreach ($name in @('clay.cmd', 'clay')) {
        $path = Join-Path $Directory $name
        if (Test-Path -LiteralPath $path) {
            Copy-Item -LiteralPath $path -Destination "$path.backup-$([guid]::NewGuid().ToString('N'))"
        }
    }
    $cmdShim = "@echo off`r`nwsl.exe -d $Distro -u $LinuxUser --exec /usr/local/bin/clay-windows %*`r`nexit /b %ERRORLEVEL%`r`n"
    [IO.File]::WriteAllText((Join-Path $Directory 'clay.cmd'), $cmdShim, [Text.ASCIIEncoding]::new())
    Write-LfFile (Join-Path $Directory 'clay') ($bashShim + "`n")
}

function Get-MigrationScript {
    # BEGIN_WSL_MIGRATION
    return @'
#!/usr/bin/env bash
set -euo pipefail
stage=$1
target=$2
source "$stage/cli-install-common.sh"
bridge=/usr/local/bin/clay-windows
# Refuse to replace files that do not belong to this bridge.
if [ -e "$bridge" ] || [ -L "$bridge" ]; then
    if ! clay_is_legacy "$bridge" && ! grep -q 'clay-cli-windows independent bridge' "$bridge"; then
        printf 'Unrecognized file at %s; inspect it before continuing.\n' "$bridge" >&2
        exit 1
    fi
    backup=$(mktemp /usr/local/bin/clay-windows.backup.XXXXXX)
    cp -p "$bridge" "$backup"
    printf 'Bridge backup: %s\n' "$backup"
fi
install -m 0755 "$stage/forwarder.sh" "$bridge"
# Early Windows bridge versions invoked /usr/local/bin/clay. Migrate only
# recognized legacy launchers; native/npm executables at this path stay intact.
if clay_is_legacy /usr/local/bin/clay; then
    backup=$(mktemp /usr/local/bin/clay.legacy.XXXXXX)
    cp -p /usr/local/bin/clay "$backup"
    link=$(mktemp /usr/local/bin/.clay-link.XXXXXX)
    rm "$link"
    ln -s "$target" "$link"
    mv -Tf "$link" /usr/local/bin/clay
    printf 'Legacy forwarder backup: %s\n' "$backup"
elif [ ! -e /usr/local/bin/clay ] && [ ! -L /usr/local/bin/clay ]; then
    ln -s "$target" /usr/local/bin/clay
fi
'@
    # END_WSL_MIGRATION
}

$script:ExplicitDistro = $PSBoundParameters.ContainsKey('Distro')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This installer is only for Windows.' }
Write-Host 'Clay CLI for Windows v0.3.0 (independent CLI bridge)' -ForegroundColor Green
$existingClay = Get-Command clay -ErrorAction SilentlyContinue
if ($existingClay) { Write-Host "Existing clay command: $($existingClay.Source)" }
$minimum = Get-MinimumVersion
if ($DryRun) {
    Write-Host "Would install/migrate the independent CLI in WSL ($Distro), minimum $minimum."
    Write-Host "Windows command: $(Join-Path $InstallRoot 'bin\clay.cmd')"
    Write-Host 'No downloads, files, PATH entries, or authentication were changed.'
    return
}

$selectedDistro = Install-WslIfNeeded
if ($selectedDistro -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw 'Unsupported WSL distribution name.' }
$userOutput = & wsl.exe -d $selectedDistro --exec id -un
if ($LASTEXITCODE -ne 0) { throw "Open $selectedDistro once to finish creating its Linux user, then rerun this installer." }
$linuxUser = ($userOutput -join '').Trim()
if ($linuxUser -notmatch '^[a-zA-Z_][a-zA-Z0-9_-]*[$]?$') { throw 'Could not identify the WSL user.' }

$stage = Join-Path ([IO.Path]::GetTempPath()) ('clay-windows-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    Write-Step "Preparing the official installer (minimum CLI $minimum)"
    foreach ($name in @('install-cli.sh', 'cli-install-common.sh')) {
        $url = "https://raw.githubusercontent.com/clay-run/agent-plugins/$UpstreamRevision/clay/scripts/$name"
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing
        Write-LfFile (Join-Path $stage $name) $response.Content
    }
    Write-LfFile (Join-Path $stage 'bootstrap.sh') (Get-BootstrapScript)
    $stageWsl = ConvertTo-WslPath $stage
    Write-Step "Installing/verifying Clay for $linuxUser in $selectedDistro"
    & wsl.exe -d $selectedDistro -u $linuxUser --exec bash "$stageWsl/bootstrap.sh" $stageWsl $minimum
    if ($LASTEXITCODE -ne 0) { throw 'Official CLI installation failed. Resolve the error above and rerun; do not switch installation methods blindly.' }
    $executable = (Get-Content -Raw -LiteralPath (Join-Path $stage 'cli-path')).Trim()
    Write-LfFile (Join-Path $stage 'forwarder.sh') (Get-ForwarderScript $executable)
    Write-LfFile (Join-Path $stage 'migrate.sh') (Get-MigrationScript)
    & wsl.exe -d $selectedDistro -u root --exec bash "$stageWsl/migrate.sh" $stageWsl $executable
    if ($LASTEXITCODE -ne 0) { throw 'CLI installed, but the bridge migration failed. See the error above.' }

    $windowsBin = Join-Path $InstallRoot 'bin'
    $windowsShim = Join-Path $windowsBin 'clay.cmd'
    Write-WindowsShims $windowsBin $selectedDistro $linuxUser
    if (-not $SkipPathUpdate) { Add-ToUserPath $windowsBin }
    & $windowsShim --version
    if ($LASTEXITCODE -ne 0) { throw 'Windows bridge verification failed.' }
    if (-not $SkipLogin) {
        & $windowsShim whoami
        if ($LASTEXITCODE -eq 3) {
            Write-Step 'Signing in to Clay'
            & $windowsShim login
            if ($LASTEXITCODE -ne 0) { throw 'Complete Clay sign-in, then run clay whoami.' }
            & $windowsShim whoami
        }
        if ($LASTEXITCODE -ne 0) { throw 'Authentication check failed. Existing credentials were not removed; inspect the error above.' }
    }
    Write-Host "Bridge ready: $windowsShim" -ForegroundColor Green
    Write-Host "Independent CLI: $executable"
    Write-Host 'Open a new terminal / restart your coding app, then run: Get-Command clay -All'
    Write-Host 'Verify: clay whoami. Update the CLI with: clay update. Update the plugin separately.'
}
finally {
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolvedStage.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedStage) -match '^clay-windows-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}
