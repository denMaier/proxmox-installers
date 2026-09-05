# Technitium DNS cluster LXC

This repository creates a Debian 13 LXC on Proxmox VE and deploys Technitium
DNS Server as a pinned Podman Quadlet. It uses the Community Scripts
`build.func` for the Proxmox menus, template download, storage selection,
networking, SSH setup, and LXC lifecycle.

The application-specific part can:

- create a standalone Technitium server;
- initialize a new cluster primary;
- join an existing cluster as a secondary and wait until it is connected;
- stage or start a health-checked keepalived VIP;
- update the Quadlet to the Technitium version in [`VERSION`](VERSION).

## Create a node

Run this command as `root` on the Proxmox node where the LXC should live:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/denMaier/technitium-cluster-lxc/main/ct/technitiumdns.sh)"
```

Choose **Advanced Install** when you want to set the static address, VMID,
hostname, storage, gateway, DNS servers, or SSH access. After the Proxmox
settings, the script asks whether the server should join a cluster, initialize
a primary, or remain standalone.

For a cluster join, enter the existing primary's IPv4 address and shared
`admin` password. The password is entered through a masked dialog, briefly
passes through a root-only file in the Proxmox host's `/run` tmpfs, and is
deleted there immediately after transfer. It is stored as mode `0600` at
`/opt/technitium/admin-password` inside the new guest. Technitium then copies
the cluster configuration and applications from the primary.

The finished server is available at `http://NODE_IP:5380/`.

## Defaults

| Setting | Default |
| --- | --- |
| OS | Debian 13 |
| Container | Unprivileged |
| CPU | 2 cores |
| Memory | 2048 MiB |
| Root disk | 8 GiB |
| Tags | `dns;infra` |
| Technitium image | `docker.io/technitium/dns-server:15.4.0` |
| Container networking | Host networking |
| DNS recursion | Private networks only |
| Keepalived | Disabled unless requested |

The Community Scripts advanced menu can override the LXC defaults. A DNS
server should have a static address or a fixed DHCP reservation.

## Keepalived

Keepalived is optional. The installer asks for the VIP, priority, virtual
router ID, peer addresses, and a shared VRRP password. An empty peer list uses
multicast. A nonempty list creates a unicast configuration.

Unicast peer lists must be reciprocal. Existing members must include the new
node before it starts keepalived, or the new node may claim the VIP because it
cannot receive their advertisements. The interactive installer therefore
offers to stage the configuration without enabling it.

After updating the existing members, start a staged node with:

```bash
pct exec CTID -- systemctl enable --now keepalived
```

## Unattended creation

All Technitium settings can be supplied as environment variables. The
lowercase `var_*` settings are handled by the Community Scripts engine.

```bash
read -rsp "Technitium admin password: " TDNS_ADMIN_PASSWORD
echo
export TDNS_ADMIN_PASSWORD

PHS_SILENT=1 \
TDNS_NONINTERACTIVE=1 \
TDNS_ROLE=join \
TDNS_PRIMARY_IP=192.168.1.53 \
var_ctid=153 \
var_hostname=dns-secondary \
var_net=192.168.1.54/24 \
var_gateway=192.168.1.1 \
var_template_storage=local \
var_container_storage=local-lvm \
mode=default \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/denMaier/technitium-cluster-lxc/main/ct/technitiumdns.sh)"

unset TDNS_ADMIN_PASSWORD
```

Set both storage variables on hosts with multiple eligible storage pools;
otherwise the Community Scripts engine asks you to choose them.

Supported application variables:

| Variable | Values or format |
| --- | --- |
| `TDNS_ROLE` | `join`, `primary`, or `standalone` |
| `TDNS_PRIMARY_IP` | Existing primary IPv4 address for `join` |
| `TDNS_ADMIN_USER` | `admin` |
| `TDNS_ADMIN_PASSWORD` | Existing shared password for `join`; generated when omitted for other roles |
| `TDNS_PRIMARY_TOTP` | Current TOTP code when the primary requires it |
| `TDNS_CLUSTER_DOMAIN` | Cluster domain for `primary` |
| `TDNS_KEEPALIVED` | `0` or `1` |
| `TDNS_VIP_CIDR` | VIP such as `192.168.1.53/24` |
| `TDNS_KEEPALIVED_PRIORITY` | `1` through `254` |
| `TDNS_VRID` | `1` through `255` |
| `TDNS_KEEPALIVED_PEERS` | Comma-separated IPv4 addresses; empty means multicast |
| `TDNS_KEEPALIVED_PASSWORD` | Shared VRRP password, 1-8 safe ASCII characters |
| `TDNS_KEEPALIVED_ENABLE_NOW` | `0` stages the configuration; `1` starts it |

## Operations

Show cluster state inside a deployed guest:

```bash
technitium-cluster-node status
```

Update a deployed guest to the version currently pinned by this repository:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/denMaier/technitium-cluster-lxc/main/ct/technitiumdns.sh)"
```

Technitium data persists under `/opt/technitium/config`. The Quadlet is
`/etc/containers/systemd/technitium.container`.

## Scope

This installer manages the LXC, Technitium, cluster membership, and optional
keepalived configuration. Services such as Twingate are separate because each
connector needs its own credentials.

The project is MIT licensed. The LXC creation flow loads the separately
maintained, MIT-licensed
[Community Scripts core](https://github.com/community-scripts/core) at runtime.
