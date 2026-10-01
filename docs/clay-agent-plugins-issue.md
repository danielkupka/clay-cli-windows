# Suggested issue for `clay-run/agent-plugins`

## Title

Document a community WSL bootstrap for Windows-only users

## Body

Clay's independent CLI supports Linux and macOS, while the setup skill and `GETTING_STARTED.md` are written around POSIX paths and shell behavior. Windows users can run the official Linux CLI through WSL, but getting there requires several manual steps:

1. Install or enable WSL.
2. Install the independent Linux CLI using Clay's official installation scripts and checksum verification.
3. Migrate older plugin-cache forwarders while preserving the installation method and sign-in.
4. Add a Windows command shim to `PATH`.
5. Keep CLI and plugin updates independent so plugin-cache changes do not break the shim.

I prepared a small community bootstrap that automates those steps:

https://github.com/danielkupka/clay-cli-windows

One-line PowerShell install:

```powershell
irm https://raw.githubusercontent.com/danielkupka/clay-cli-windows/v0.3.0/install.ps1 | iex
```

Would the Clay team be open to linking this from `GETTING_STARTED.md` or the setup skill's Windows troubleshooting section? The wrapper runs Clay's official independent CLI; it does not reimplement the CLI or its authentication. It is an unofficial community solution, used at the user's own risk.
