[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Distro = 'Ubuntu-24.04',

    [ValidateNotNullOrEmpty()]
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\ClayCLI'),

    [switch]$SkipLogin,
    [switch]$SkipPathUpdate,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OfficialArchiveUrl = 'https://github.com/clay-run/agent-plugins/archive/refs/heads/main.zip'

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WslDistros {
    $rawNames = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    return @(
        $rawNames |
            ForEach-Object { ($_ -replace "`0", '').Trim() } |
            Where-Object { $_ -and $_ -notlike 'docker-desktop*' }
    )
}

function ConvertTo-WslPath {
    param([Parameter(Mandatory)][string]$WindowsPath)

    $fullPath = [IO.Path]::GetFullPath($WindowsPath)
    if ($fullPath -notmatch '^([A-Za-z]):\\(.*)$') {
        throw "Only local drive paths are supported: $fullPath"
    }

    $drive = $Matches[1].ToLowerInvariant()
    $tail = $Matches[2].Replace('\', '/')
    return "/mnt/$drive/$tail"
}

function ConvertTo-ShellSingleQuoted {
    param([Parameter(Mandatory)][string]$Value)
    $embeddedQuote = "'" + '"' + "'" + '"' + "'"
    return "'" + $Value.Replace("'", $embeddedQuote) + "'"
}

function Find-ClayLauncher {
    $patterns = @(
        (Join-Path $env:USERPROFILE '.codex\plugins\cache\*\clay\*\bin\clay'),
        (Join-Path $env:USERPROFILE '.claude\plugins\cache\*\clay\*\bin\clay'),
        (Join-Path $env:USERPROFILE '.cursor\plugins\cache\*\clay\*\bin\clay'),
        (Join-Path $env:USERPROFILE '.cursor\plugins\local\clay\bin\clay'),
        (Join-Path $env:USERPROFILE '.config\clay-plugin\clay\bin\clay')
    )

    $launcherCandidates = foreach ($pattern in $patterns) {
        Get-Item -Path $pattern -ErrorAction SilentlyContinue
    }

    return $launcherCandidates | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
}

function Install-WslIfNeeded {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'wsl.exe is unavailable. Install WSL from Microsoft, restart Windows, and rerun this installer.'
    }

    $availableDistros = @(Get-WslDistros)
    if ($availableDistros -contains $Distro) {
        return $Distro
    }

    if ($availableDistros.Count -gt 0) {
        Write-Host "Using existing WSL distribution: $($availableDistros[0])"
        return $availableDistros[0]
    }

    if ($DryRun) {
        Write-Host "[dry run] Would install WSL distribution $Distro."
        return $Distro
    }

    Write-Step "Installing WSL and $Distro"
    Write-Host 'Windows may show an administrator approval prompt.'

    $arguments = @('--install', '--distribution', $Distro, '--no-launch')
    if (Test-IsAdministrator) {
        $process = Start-Process -FilePath 'wsl.exe' -ArgumentList $arguments -Wait -PassThru
    }
    else {
        $process = Start-Process -FilePath 'wsl.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    }

    if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
        throw "WSL installation failed with exit code $($process.ExitCode)."
    }

    $availableDistros = @(Get-WslDistros)
    if ($availableDistros -notcontains $Distro) {
        throw "Windows needs to restart to finish installing WSL. Restart, then paste the same installer command again."
    }

    return $Distro
}

function Copy-OfficialLauncher {
    param([Parameter(Mandatory)][string]$Destination)

    $downloadRoot = $null
    try {
        $launcher = Find-ClayLauncher
        if ($launcher) {
            Write-Host "Using Clay launcher from $($launcher.FullName)"
            $sourceBin = $launcher.Directory.FullName
        }
        else {
            Write-Step 'Downloading the official Clay launcher'
            $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) ("clay-cli-windows-" + [guid]::NewGuid().ToString('N'))
            $archivePath = Join-Path $downloadRoot 'agent-plugins.zip'
            $extractPath = Join-Path $downloadRoot 'extract'

            New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
            Invoke-WebRequest -Uri $OfficialArchiveUrl -OutFile $archivePath -UseBasicParsing
            Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force
            $sourceBin = Join-Path $extractPath 'agent-plugins-main\clay\bin'
            if (-not (Test-Path -LiteralPath (Join-Path $sourceBin 'clay'))) {
                throw 'The downloaded Clay repository did not contain clay/bin/clay.'
            }
        }

        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        foreach ($name in @('clay', 'cli-version', 'checksums.txt')) {
            $sourceFile = Join-Path $sourceBin $name
            if (-not (Test-Path -LiteralPath $sourceFile)) {
                throw "The Clay launcher is incomplete: missing $name."
            }
            Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $Destination $name) -Force
        }
    }
    finally {
        if ($downloadRoot -and (Test-Path -LiteralPath $downloadRoot)) {
            Remove-Item -LiteralPath $downloadRoot -Recurse -Force
        }
    }
}

function New-WslForwarder {
    param(
        [Parameter(Mandatory)][string]$WindowsHomeWsl,
        [Parameter(Mandatory)][string]$VendorLauncherWsl
    )

    $quotedHome = ConvertTo-ShellSingleQuoted $WindowsHomeWsl
    $quotedVendor = ConvertTo-ShellSingleQuoted $VendorLauncherWsl

    # BEGIN_WSL_FORWARDER
    $template = @'
#!/bin/sh
set -eu

windows_home=__WINDOWS_HOME_WSL__
vendor_launcher=__VENDOR_LAUNCHER_WSL__

# Prefer the newest launcher installed by Codex, Claude Code, or Cursor. The
# vendored launcher copied by install.ps1 is a stable fallback.
launcher="$(ls -1dt \
  "$windows_home"/.codex/plugins/cache/*/clay/*/bin/clay \
  "$windows_home"/.claude/plugins/cache/*/clay/*/bin/clay \
  "$windows_home"/.cursor/plugins/cache/*/clay/*/bin/clay \
  "$windows_home"/.cursor/plugins/local/clay/bin/clay \
  "$windows_home"/.config/clay-plugin/clay/bin/clay \
  "$vendor_launcher" \
  2>/dev/null | head -n1)"

if [ -z "$launcher" ] || [ ! -f "$launcher" ]; then
  printf '%s\n' '{"error":{"code":"internal_error","message":"clay: no bundled launcher found; rerun the Windows installer"}}' >&2
  exit 127
fi

source_bin="$(dirname "$launcher")"
for required in clay cli-version checksums.txt; do
  if [ ! -f "$source_bin/$required" ]; then
    printf '%s\n' "clay: launcher is incomplete; missing $required" >&2
    exit 127
  fi
done

version="$(tr -d '\r\n' < "$source_bin/cli-version")"
normalized_bin="${XDG_CACHE_HOME:-$HOME/.cache}/clay-windows-launcher/$version"
mkdir -p "$normalized_bin"

# Plugin files may have CRLF line endings on the Windows mount. Normalize the
# launcher metadata inside WSL before executing it.
for name in clay cli-version checksums.txt; do
  temporary="$normalized_bin/$name.$$.tmp"
  tr -d '\r' < "$source_bin/$name" > "$temporary"
  mv "$temporary" "$normalized_bin/$name"
done
chmod 0755 "$normalized_bin/clay"

exec "$normalized_bin/clay" "$@"
'@
    # END_WSL_FORWARDER

    return $template.Replace('__WINDOWS_HOME_WSL__', $quotedHome).Replace('__VENDOR_LAUNCHER_WSL__', $quotedVendor)
}

function Add-ToUserPath {
    param([Parameter(Mandatory)][string]$Directory)

    $currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @($currentUserPath -split ';' | Where-Object { $_ })
    $alreadyPresent = $entries | Where-Object { $_.TrimEnd('\') -ieq $Directory.TrimEnd('\') }
    if ($alreadyPresent) {
        return
    }

    $updatedPath = (($entries + $Directory) -join ';') + ';'
    [Environment]::SetEnvironmentVariable('Path', $updatedPath, 'User')
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This installer is only for Windows.'
}

Write-Host 'Clay CLI for Windows (WSL bridge)' -ForegroundColor Green
Write-Host 'This installs a Windows command shim; the official Clay Linux CLI runs inside WSL.'

$selectedDistro = Install-WslIfNeeded
$vendorBin = Join-Path $InstallRoot 'vendor\clay\bin'
$windowsBin = Join-Path $InstallRoot 'bin'
$windowsShim = Join-Path $windowsBin 'clay.cmd'

if ($DryRun) {
    Write-Step 'Dry-run summary'
    Write-Host "WSL distribution: $selectedDistro"
    Write-Host "Install root: $InstallRoot"
    Write-Host "Windows shim: $windowsShim"
    Write-Host 'No files, PATH entries, or authentication state were changed.'
    exit 0
}

Write-Step 'Staging the official Clay launcher'
Copy-OfficialLauncher -Destination $vendorBin

Write-Step 'Installing the WSL forwarder'
$windowsHomeWsl = ConvertTo-WslPath $env:USERPROFILE
$vendorLauncherWsl = ConvertTo-WslPath (Join-Path $vendorBin 'clay')
$forwarder = New-WslForwarder -WindowsHomeWsl $windowsHomeWsl -VendorLauncherWsl $vendorLauncherWsl
$temporaryForwarder = Join-Path ([IO.Path]::GetTempPath()) ("clay-wsl-" + [guid]::NewGuid().ToString('N') + '.sh')
[IO.File]::WriteAllText($temporaryForwarder, ($forwarder -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))

try {
    $temporaryForwarderWsl = ConvertTo-WslPath $temporaryForwarder
    & wsl.exe -d $selectedDistro -u root --exec install -m 0755 $temporaryForwarderWsl /usr/local/bin/clay-windows
    if ($LASTEXITCODE -ne 0) {
        throw "Could not install /usr/local/bin/clay-windows inside $selectedDistro."
    }
}
finally {
    Remove-Item -LiteralPath $temporaryForwarder -Force -ErrorAction SilentlyContinue
}

Write-Step 'Installing the Windows command'
New-Item -ItemType Directory -Path $windowsBin -Force | Out-Null
$shimContent = "@echo off`r`nwsl.exe -d $selectedDistro --exec /usr/local/bin/clay-windows %*`r`nexit /b %ERRORLEVEL%`r`n"
[IO.File]::WriteAllText($windowsShim, $shimContent, [Text.ASCIIEncoding]::new())

if (-not $SkipPathUpdate) {
    Add-ToUserPath -Directory $windowsBin
}

Write-Step 'Verifying the installation'
& $windowsShim --version
if ($LASTEXITCODE -ne 0) {
    throw 'Clay was installed, but the version check failed.'
}

if (-not $SkipLogin) {
    & $windowsShim whoami
    if ($LASTEXITCODE -eq 3) {
        Write-Step 'Signing in to Clay'
        & $windowsShim login
        if ($LASTEXITCODE -ne 0) {
            throw 'Clay login did not complete successfully.'
        }
        & $windowsShim whoami
    }
    if ($LASTEXITCODE -ne 0) {
        throw 'Clay authentication verification failed.'
    }
}

Write-Host "`nClay is ready." -ForegroundColor Green
Write-Host 'Open a new PowerShell window, then run: clay whoami'
