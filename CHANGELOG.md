# Changelog

## 0.3.0

- Use Clay's independent CLI instead of looking for a removed plugin-bundled launcher.
- Run the official installer from a pinned upstream commit; enforce the installed plugins' minimum CLI version (at least 1.4.0).
- Preserve compatible native/npm installations and existing sign-in. Back up recognized legacy bridges before migrating them; refuse unrecognized Linux executables.
- Pin the WSL user in the Windows shim and repair recognized early `/usr/local/bin/clay` forwarders.
- Fix Windows PATH concatenation and deduplication.
- Document migration, separate CLI/plugin updates, and the current `searches` skill name.
- Add PATH, shell syntax, quoted argument, and exit-code regression tests.

Existing users: rerun the README's installer command, then restart your terminal/coding app. No plugin reinstall or credential deletion is needed.
