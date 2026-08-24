# Clay CLI for Windows

A small Windows-to-WSL bridge for Clay's official agent plugin and CLI.

Clay currently ships Linux and macOS launchers but no native Windows executable. This installer keeps Windows as the host operating system, installs or reuses WSL, and exposes a normal `clay` command to PowerShell, Codex, Claude Code, and Cursor.

## The short answer

**You do not need to clone or install the `clay-run/agent-plugins` GitHub repository first.** Run the PowerShell installer below directly.

- If the Clay plugin is already installed in Codex, Claude Code, or Cursor, the installer reuses its official launcher.
- If the plugin is not installed, the installer downloads the official launcher from `clay-run/agent-plugins` for you.
- Installing the **agent plugin** is a separate step. It adds Clay's skills and natural-language guidance to your coding app; the Windows installer adds the working `clay` command.

| Piece | Purpose | Installed by |
| --- | --- | --- |
| WSL | Runs Clay's official Linux binary on Windows | This installer, when needed |
| Clay CLI and Windows `clay` command | Provides search, routines, tables, workflows, and authentication | This installer |
| Clay agent plugin | Teaches Codex, Claude Code, or Cursor how and when to use the CLI | You install it inside the app |

If you only want to run Clay commands from PowerShell, the plugin is optional. If you want to ask for Clay work naturally inside Codex, Claude Code, or Cursor, install the plugin too.

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

## Recommended Windows setup order

1. Run the one-line PowerShell installer above.
2. Complete the Clay browser login if prompted.
3. Confirm that `clay whoami` returns your user and workspace.
4. Install the Clay plugin in your coding app using the app-specific instructions below.
5. Fully quit and reopen the coding app so it sees the new PATH entry and plugin.
6. Start a new chat and ask for the Clay task in normal language.

Installing the plugin before the Windows bridge also works. The bridge automatically reuses the newest launcher it finds.

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

## Use Clay inside your coding app

The Windows bridge and the app plugin work together:

- The bridge makes `clay` executable on Windows.
- The plugin supplies skills such as Clay Search, Audiences, Routines, Tables, and Workflows.
- You normally ask for the outcome in plain language; you do not have to type CLI commands yourself.

### Codex

Install the marketplace:

```powershell
codex plugin marketplace add clay-run/agent-plugins
```

Then:

1. Open **Plugins** in Codex and install **clay**.
2. Fully quit and reopen Codex.
3. Create a new task and ask, for example:

```text
Use Clay to find 20 fintech companies in Berlin and save two decision-makers per company to Audiences.
```

Codex should select the appropriate `clay:*` skills automatically. You can be explicit when useful:

```text
Use $clay:search to find the companies, then $clay:audiences to save the contacts.
```

### Claude Code

Run these slash commands inside Claude Code:

```text
/plugin marketplace add clay-run/agent-plugins
/plugin install clay@clay-plugins
```

Fully quit and reopen Claude Code, then ask naturally:

```text
Use Clay to find ten SEO agencies in Hamburg and identify two decision-makers at each.
```

### Cursor

Cursor installation can depend on your Teams or Enterprise plugin policy. Follow Clay's current [`GETTING_STARTED.md`](https://github.com/clay-run/agent-plugins/blob/main/GETTING_STARTED.md) for the plugin installation path that applies to your account.

If you hand the setup to Cursor's agent, use this prompt:

```text
Install the Clay plugin for Cursor by following its official GETTING_STARTED.md. The Windows Clay CLI bridge is already installed, so verify it with `clay whoami` instead of replacing it.
```

After the plugin appears, fully quit and reopen Cursor. Start a new chat and ask for the Clay task in normal language.

### PowerShell without an app plugin

The CLI also works directly:

```powershell
clay whoami
clay --help
clay search --help
clay routines list
```

The workspace comes from the session created by `clay login`; you do not need to pass a workspace ID.

## Do I still run `clay:setup`?

Usually, no. This Windows installer already handles the CLI, PATH, login, and verification work that the setup skill would normally perform.

Use `clay:setup` only if:

- `clay whoami` fails;
- the CLI version is wrong; or
- your coding app cannot see the Clay plugin after a restart.

For a healthy installation, open a new chat and go directly to your Clay request.

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

