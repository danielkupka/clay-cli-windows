# Clay CLI for Windows

A small Windows-to-WSL bridge for Clay's official agent plugin and CLI.

Clay currently ships Linux and macOS launchers but no native Windows executable. This installer keeps Windows as the host operating system, installs or reuses WSL, and exposes a normal `clay` command to PowerShell, Codex, Claude Code, and Cursor.

## One-line installation

Open **PowerShell** and paste:

```powershell
irm https://raw.githubusercontent.com/danielkupka/clay-cli-windows/v0.1.0/install.ps1 | iex
```

The installer may request administrator approval if WSL is not enabled. If Windows asks for a restart, restart and paste the same line again.

After installation:

```powershell
clay whoami
```

If you are not signed in yet, the installer starts `clay login` and opens Clay's browser sign-in flow.

## What the installer does

1. Reuses an existing non-Docker WSL distribution, or installs Ubuntu 24.04.
2. Finds the newest official Clay launcher in the Codex, Claude Code, or Cursor plugin cache.
3. If the plugin is not installed yet, downloads the launcher directly from [`clay-run/agent-plugins`](https://github.com/clay-run/agent-plugins).
4. Installs a CRLF-safe forwarder at `/usr/local/bin/clay-windows` inside WSL.
5. Creates `%LOCALAPPDATA%\Programs\ClayCLI\bin\clay.cmd`.
6. Adds that directory to the current user's permanent `PATH`.
7. Verifies the CLI version and authentication.

The wrapper resolves the newest installed plugin launcher every time it runs, so normal plugin upgrades do not require repointing it.

## Requirements

- Windows 10 version 2004 or newer, or Windows 11
- PowerShell 5.1 or newer
- Internet access during installation and the first Clay CLI launch
- Permission to enable WSL if it is not already installed

You do not need to install Linux as the host operating system. WSL is the compatibility layer used only for the Clay binary.

## Install the Clay agent plugin

The wrapper makes the CLI available. For the Clay skills inside your coding agent, also install the official plugin:

### Codex

```powershell
codex plugin marketplace add clay-run/agent-plugins
```

Then open **Plugins** in Codex and install **clay**.

### Claude Code

```text
/plugin marketplace add clay-run/agent-plugins
/plugin install clay@clay-plugins
```

For Cursor and current agent-specific instructions, follow Clay's official [`GETTING_STARTED.md`](https://github.com/clay-run/agent-plugins/blob/main/GETTING_STARTED.md).

## Safer review-first installation

If your security policy does not allow piping a downloaded script directly into PowerShell:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/danielkupka/clay-cli-windows/v0.1.0/install.ps1 -OutFile install-clay-windows.ps1
notepad .\install-clay-windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-clay-windows.ps1
```

## Options

Download the script first, then pass any of these options:

```powershell
.\install-clay-windows.ps1 -Distro Ubuntu-22.04
.\install-clay-windows.ps1 -SkipLogin
.\install-clay-windows.ps1 -SkipPathUpdate
.\install-clay-windows.ps1 -DryRun
```

## Troubleshooting

### Windows says a restart is required

Restart Windows, open PowerShell, and paste the same installation line again. The installer is idempotent.

### `clay` is not recognized after installation

Open a new PowerShell or fully restart your coding agent. Existing processes keep the `PATH` they had when they started.

### The plugin is installed but the launcher fails in WSL

Rerun the installer. It copies the required launcher metadata and normalizes Windows CRLF line endings before execution.

### A command with complex JSON loses its quoting

The `.cmd` shim is intended for ordinary Clay commands. For complex nested JSON or advanced queries, call the WSL command directly:

```powershell
wsl.exe -d Ubuntu-24.04 --exec /usr/local/bin/clay-windows <command> <arguments>
```

### Verify each layer

```powershell
wsl.exe --list --verbose
Get-Command clay
clay --version
clay whoami
```

## Scope and licensing

This repository contains only the Windows bridge and installer. The Clay launcher and CLI are downloaded from Clay's official repository at installation time and remain governed by Clay's terms. The wrapper code in this repository is MIT licensed.

