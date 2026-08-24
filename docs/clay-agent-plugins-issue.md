# Suggested issue for `clay-run/agent-plugins`

## Title

Document a community WSL bootstrap for Windows-only users

## Body

Clay's bundled launcher currently rejects Windows hosts, while the setup skill and `GETTING_STARTED.md` are written around POSIX paths and shell behavior. Windows users can still run the official Linux CLI reliably through WSL, but getting there currently requires several manual steps:

1. Install or enable WSL.
2. Locate the newest launcher inside the agent's Windows plugin cache.
3. Normalize CRLF line endings for the POSIX launcher and checksum manifest.
4. Add a Windows command shim to `PATH`.
5. Preserve the dynamic launcher lookup so plugin upgrades do not break the shim.

I prepared a small community bootstrap that automates those steps:

https://github.com/danielkupka/clay-cli-windows

One-line PowerShell install:

```powershell
irm https://raw.githubusercontent.com/danielkupka/clay-cli-windows/v0.2.0/install.ps1 | iex
```

Would the Clay team be open to linking this from `GETTING_STARTED.md` or the setup skill's Windows troubleshooting section? The wrapper still downloads and runs Clay's official launcher; it does not reimplement the CLI or its authentication.
