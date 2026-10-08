[CmdletBinding()]
param([string]$GitBash = (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Run this regression test with Windows PowerShell 5.1.' }
. (Join-Path $PSScriptRoot 'Test-Installer.ps1')

$testRoot = Join-Path $repositoryRoot ('.test-output\windows-' + [guid]::NewGuid().ToString('N'))
$nativeBin = Join-Path $testRoot 'native'
$shimBin = Join-Path $testRoot 'shim bin'
New-Item -ItemType Directory -Path $nativeBin -Force | Out-Null
Add-Type -TypeDefinition (Get-Content -Raw (Join-Path $PSScriptRoot 'FakeWsl.cs')) -OutputAssembly (Join-Path $nativeBin 'wsl.exe') -OutputType ConsoleApplication
$previousPath = $env:Path
$previousMode = $env:CLAY_TEST_WSL_MODE
try {
    $env:Path = "$nativeBin;$previousPath"
    Push-Location $nativeBin
    try {
        $env:CLAY_TEST_WSL_MODE = 'missing'
        $oldBehaviorFailed = $false
        try { & wsl.exe --list --quiet 2>$null | Out-Null } catch { $oldBehaviorFailed = $true }
        if (-not $oldBehaviorFailed) { throw 'Fixture did not reproduce the PowerShell 5.1 native stderr regression.' }
        Assert-Equal @(Get-WslDistros).Count 0 'Native stderr with Stop must not terminate discovery'
        $env:CLAY_TEST_WSL_MODE = 'distros'
        Assert-Equal (@(Get-WslDistros) -join '|') 'Ubuntu-24.04|Debian' 'NUL stripping and Docker filtering'
        foreach ($mode in @('empty', 'docker')) {
            $env:CLAY_TEST_WSL_MODE = $mode
            Assert-Equal @(Get-WslDistros).Count 0 "Empty discovery: $mode"
        }

        # Ensure an unavailable WSL reaches the install branch. Never install WSL.
        $env:CLAY_TEST_WSL_MODE = 'missing'
        $script:ExplicitDistro = $false
        $Distro = 'Ubuntu-24.04'
        $DryRun = $false
        $script:installationRequested = $false
        function Start-Process {
            param($FilePath, $ArgumentList, $Verb, $WindowStyle, [switch]$Wait, [switch]$PassThru)
            Assert-Equal $FilePath 'wsl.exe' 'Install executable'
            Assert-Equal ($ArgumentList -join ' ') '--install --distribution Ubuntu-24.04 --no-launch' 'Install arguments'
            $script:installationRequested = $true
            return [pscustomobject]@{ ExitCode = 3010 }
        }
        try {
            $restartReported = $false
            try { Install-WslIfNeeded | Out-Null } catch {
                if ($_.Exception.Message -notlike 'Restart Windows*') { throw }
                $restartReported = $true
            }
            if (-not $script:installationRequested -or -not $restartReported) { throw 'First-run installation branch was not reached.' }
        } finally { Remove-Item Function:\Start-Process }
    } finally { Pop-Location }

    Write-WindowsShims $shimBin 'Ubuntu-24.04' 'test-user$'
    $shellBytes = [IO.File]::ReadAllBytes((Join-Path $shimBin 'clay'))
    if ($shellBytes[0] -ne 35 -or $shellBytes[1] -ne 33 -or $shellBytes -contains 13) { throw 'Shell shim must have no BOM and use LF.' }
    foreach ($name in @('clay', 'clay.cmd')) {
        [IO.File]::WriteAllText((Join-Path $shimBin $name), "old $name")
    }
    Write-WindowsShims $shimBin 'Ubuntu-24.04' 'test-user$'
    foreach ($name in @('clay', 'clay.cmd')) {
        $backups = @(Get-ChildItem -LiteralPath $shimBin -Filter "$name.backup-*")
        Assert-Equal $backups.Count 1 "Backup count: $name"
        Assert-Equal ([IO.File]::ReadAllText($backups[0].FullName)) "old $name" "Backup content: $name"
    }
    if (-not (Test-Path -LiteralPath $GitBash)) { throw "Git Bash missing: $GitBash" }
    $env:CLAY_TEST_WSL_MODE = 'forward'
    & $GitBash --noprofile --norc (Join-Path $PSScriptRoot 'Test-GitBash.sh') $shimBin $nativeBin
    if ($LASTEXITCODE -ne 0) { throw 'Git Bash integration test failed.' }
} finally {
    $env:Path = $previousPath
    $env:CLAY_TEST_WSL_MODE = $previousMode
}
Write-Host 'PowerShell 5.1 WSL discovery, first-run branch, shim backups, and Git Bash integration passed.'
