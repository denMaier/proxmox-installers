# Proxmox installers

This repository contains reusable Proxmox VE LXC installers built on the
[Community Scripts core](https://github.com/community-scripts/core). Each
installer provides the familiar Proxmox Helper Scripts menus while keeping its
application setup and update logic in this repository.

## Available installers

| Application | Description | Install |
| --- | --- | --- |
| [Technitium DNS](docs/technitiumdns.md) | Debian 13 LXC with Technitium DNS, optional clustering, and optional keepalived | `bash -c "$(curl -fsSL https://raw.githubusercontent.com/denMaier/proxmox-installers/main/ct/technitiumdns.sh)"` |

Run installer commands as `root` on the Proxmox node where the new LXC should
be created. See the linked application guide for defaults, interactive and
unattended setup, updates, and operational commands.

## Repository layout

```text
ct/        Proxmox-host entry points
install/   Scripts executed inside a new guest
scripts/   Runtime helpers installed into guests
versions/  Per-application version pins
docs/      Application guides
```

The entry point for an application is `ct/<application>.sh`; its guest setup
script is `install/<application>-install.sh`. New applications should use a
separate version file under `versions/` instead of a repository-wide version.
See [Adding an installer](docs/adding-an-installer.md) for the repository
conventions and checks.

## Secrets

Deployment secrets do not belong in this repository. Installers must request
credentials at runtime or generate them on the target system. Interactive
password input must be masked, temporary host-side secret files must use a
root-only mode and be removed immediately, and persistent credentials must be
stored only on the target with root-only permissions.

The repository is checked with ShellCheck and Gitleaks in CI.

## License

The project is MIT licensed. The LXC creation flow loads the separately
maintained, MIT-licensed Community Scripts core at runtime.
