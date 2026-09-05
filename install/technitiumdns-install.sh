#!/usr/bin/env bash

# Copyright (c) 2026 Denis Maier
# License: MIT
# Runs inside the Debian LXC created by ct/technitiumdns.sh.

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Podman and keepalived"
$STD apt-get install -y podman keepalived jq
msg_ok "Installed Podman and keepalived"

version="${APPLICATION_VERSION:-}"
if [[ -z "$version" ]]; then
  version="$(curl -fsSL "${COMMUNITY_SCRIPTS_URL}/versions/technitiumdns" | tr -d '[:space:]')"
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  msg_error "Invalid VERSION value: $version"
  exit 1
fi
image="docker.io/technitium/dns-server:${version}"
node_name="$(hostname | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9.-')"

msg_info "Installing Technitium DNS Server ${version}"
mkdir -p /opt/technitium/config /etc/containers/systemd
chmod 0700 /opt/technitium
podman pull "$image" >/dev/null

cat >/etc/containers/systemd/technitium.container <<EOF
[Unit]
Description=Technitium DNS Server
After=network-online.target
Wants=network-online.target

[Container]
Image=${image}
ContainerName=technitium
HostName=${node_name}
Network=host
Volume=/opt/technitium/config:/etc/dns
Volume=/opt/technitium/admin-password:/run/secrets/admin-password:ro
Environment=DNS_SERVER_DOMAIN=${node_name}
Environment=DNS_SERVER_ADMIN_PASSWORD_FILE=/run/secrets/admin-password
Environment=DNS_SERVER_RECURSION=AllowOnlyForPrivateNetworks

[Service]
Restart=on-failure
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target
EOF

cat >/usr/local/sbin/check-technitium <<'EOF'
#!/bin/sh
curl -fsS --max-time 2 http://127.0.0.1:5380/api/status |
  grep -q '"status":"ok"'
EOF
chmod 0755 /usr/local/sbin/check-technitium

systemctl daemon-reload
systemctl disable --now keepalived.service >/dev/null 2>&1 || true
msg_ok "Installed Technitium DNS Server ${version}"

motd_ssh
customize
cleanup_lxc
