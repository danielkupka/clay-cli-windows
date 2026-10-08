# Changelog

## 0.3.1 — 2026-10-08

- Handle the WSL-not-installed stderr response under Windows PowerShell 5.1 so setup can reach the WSL installation branch.
- Install an extensionless, LF-only Git Bash `clay` shim alongside `clay.cmd`, disabling MSYS path conversion and preserving the selected WSL user, arguments, and exit code. Back up both existing shims before replacement.
- Document the literal `upgrade_required` / `no longer supported. Upgrade to >= 1.3.0` symptom on old bridges.
- Add Windows PowerShell 5.1 and Git Bash regression coverage without changing the machine's WSL installation or credentials.

Existing users: rerun the README's v0.3.1 installer command, then restart your terminal/coding app to receive the Git Bash launcher. Your existing Clay sign-in is preserved.

## 0.3.0

- Use Clay's independent CLI instead of looking for a removed plugin-bundled launcher.
- Run the official installer from a pinned upstream commit; enforce the installed plugins' minimum CLI version (at least 1.4.0).
- Preserve compatible native/npm installations and existing sign-in. Back up recognized legacy bridges before migrating them; refuse unrecognized Linux executables.
- Pin the WSL user in the Windows shim and repair recognized early `/usr/local/bin/clay` forwarders.
- Fix Windows PATH concatenation and deduplication.
- Document migration, separate CLI/plugin updates, and the current `searches` skill name.
- Add PATH, shell syntax, quoted argument, and exit-code regression tests.

Existing users: rerun the README's installer command, then restart your terminal/coding app. No plugin reinstall or credential deletion is needed.
