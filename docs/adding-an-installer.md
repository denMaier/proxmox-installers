# Adding an installer

Use a short lowercase application name consistently. An installer normally
adds these files:

```text
ct/<application>.sh
install/<application>-install.sh
versions/<application>
docs/<application>.md
```

Add runtime helpers under `scripts/` only when the deployed guest needs them.
Then add the installer to the table in the repository README.

The host entry point should load the Community Scripts `build.func`, declare
its LXC defaults, and call `build_container`. Application packages and service
files belong in the guest installer. Keep application update logic in the host
entry point so rerunning the same command against an existing container uses
the version pinned under `versions/`.

Never commit credentials, API tokens, private keys, deployment-specific
addresses, or generated configuration archives. Request secrets through a
masked prompt or an environment variable at runtime. If a secret must cross
from the Proxmox host into a guest, use a mode-0600 temporary file under
`/run`, transfer it, and remove the host copy immediately.

Before committing, run:

```bash
bash -n ct/*.sh install/*.sh scripts/*
shellcheck ct/*.sh install/*.sh scripts/*
gitleaks git --redact
```
