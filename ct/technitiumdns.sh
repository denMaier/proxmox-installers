#!/usr/bin/env bash

_CS_DEFAULT_URL="${TDNS_REPO_RAW_URL:-https://raw.githubusercontent.com/denMaier/technitium-cluster-lxc/main}"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2026 Denis Maier
# License: MIT
# Uses the MIT-licensed Proxmox VE Helper-Scripts build engine.
# Sources: https://technitium.com/dns/ and https://github.com/containers/podman

APP="Technitium DNS"
_script_root="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")/.." 2>/dev/null && pwd || true)"
if [[ -f "${_script_root}/VERSION" ]]; then
  _tdns_version="$(tr -d '[:space:]' <"${_script_root}/VERSION")"
else
  _tdns_version="$(curl -fsSL "${_CS_DEFAULT_URL}/VERSION" | tr -d '[:space:]')"
fi
var_tags="${var_tags:-dns;infra}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_appversion="${var_appversion:-$_tdns_version}"
unset _script_root _tdns_version

header_info "$APP"
variables
color
catch_errors

repo_version() {
  curl -fsSL "${COMMUNITY_SCRIPTS_URL:-$_CS_DEFAULT_URL}/VERSION" | tr -d '[:space:]'
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  local quadlet="/etc/containers/systemd/technitium.container"
  if [[ ! -f "$quadlet" ]]; then
    msg_error "No ${APP} installation found"
    exit 1
  fi

  local version image helper_url
  version="$(repo_version)"
  [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || {
    msg_error "Invalid VERSION value: $version"
    exit 1
  }
  image="docker.io/technitium/dns-server:${version}"
  helper_url="${COMMUNITY_SCRIPTS_URL:-$_CS_DEFAULT_URL}/scripts/technitium-cluster-node"

  msg_info "Updating Technitium DNS Server to ${version}"
  curl -fsSL "$helper_url" -o /usr/local/sbin/technitium-cluster-node
  chmod 0755 /usr/local/sbin/technitium-cluster-node
  podman pull "$image" >/dev/null
  sed -i "s|^Image=.*|Image=${image}|" "$quadlet"
  systemctl daemon-reload
  systemctl restart technitium.service
  for _ in {1..60}; do
    if curl -fsS --max-time 2 http://127.0.0.1:5380/api/status >/dev/null; then
      msg_ok "Updated Technitium DNS Server to ${version}"
      exit 0
    fi
    sleep 1
  done
  msg_error "Technitium did not become ready after the update"
  exit 1
}

is_unattended() {
  [[ "${PHS_SILENT:-0}" == "1" || "${TDNS_NONINTERACTIVE:-0}" == "1" ]]
}

input_box() {
  local title="$1" prompt="$2" default_value="${3:-}" value
  value=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" \
    --inputbox "$prompt" 11 72 "$default_value" 3>&1 1>&2 2>&3) || exit 1
  printf '%s' "$value"
}
password_box() {
  local title="$1" prompt="$2" value
  value=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" \
    --passwordbox "$prompt" 11 72 3>&1 1>&2 2>&3) || exit 1
  printf '%s' "$value"
}

yes_no() {
  local title="$1" prompt="$2"
  whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "$title" \
    --yesno "$prompt" 11 72
}

validate_ipv4() {
  python3 - "$1" <<'PY'
import ipaddress
import sys

try:
    address = ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)
raise SystemExit(0 if address.version == 4 else 1)
PY
}

validate_ipv4_cidr() {
  python3 - "$1" <<'PY'
import ipaddress
import sys

try:
    address = ipaddress.ip_interface(sys.argv[1])
except ValueError:
    raise SystemExit(1)
raise SystemExit(0 if address.version == 4 else 1)
PY
}

collect_tdns_settings() {
  if is_unattended; then
    TDNS_ROLE="${TDNS_ROLE:-standalone}"
    TDNS_KEEPALIVED="${TDNS_KEEPALIVED:-0}"
    TDNS_KEEPALIVED_ENABLE_NOW="${TDNS_KEEPALIVED_ENABLE_NOW:-0}"
  else
    if [[ -z "${TDNS_ROLE:-}" ]]; then
      TDNS_ROLE=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
        --title "TECHNITIUM ROLE" --default-item "join" \
        --menu "Choose how this DNS server should be configured." 16 72 4 \
        "join" "Join an existing Technitium cluster as a secondary" \
        "primary" "Initialize a new Technitium cluster primary" \
        "standalone" "Create a standalone server" \
        3>&1 1>&2 2>&3) || exit 1
    fi

    case "$TDNS_ROLE" in
    join)
      TDNS_PRIMARY_IP="${TDNS_PRIMARY_IP:-$(input_box "CLUSTER PRIMARY" "IPv4 address of the existing Technitium primary:" "")}"
      TDNS_ADMIN_USER="${TDNS_ADMIN_USER:-$(input_box "CLUSTER LOGIN" "Primary cluster username:" "admin")}"
      if [[ -z "${TDNS_ADMIN_PASSWORD:-}" ]]; then
        TDNS_ADMIN_PASSWORD="$(password_box "CLUSTER LOGIN" "Password for ${TDNS_ADMIN_USER}:")"
      fi
      ;;
    primary)
      TDNS_CLUSTER_DOMAIN="${TDNS_CLUSTER_DOMAIN:-$(input_box "CLUSTER DOMAIN" "Cluster domain:" "cluster.dns.example.com")}"
      if [[ -z "${TDNS_ADMIN_PASSWORD:-}" ]]; then
        TDNS_ADMIN_PASSWORD="$(password_box "ADMIN PASSWORD" "Admin password (leave empty to generate one):")"
      fi
      ;;
    standalone)
      if [[ -z "${TDNS_ADMIN_PASSWORD:-}" ]]; then
        TDNS_ADMIN_PASSWORD="$(password_box "ADMIN PASSWORD" "Admin password (leave empty to generate one):")"
      fi
      ;;
    esac

    if [[ -z "${TDNS_KEEPALIVED:-}" ]]; then
      if yes_no "FLOATING DNS ADDRESS" "Stage keepalived for a floating DNS address?"; then
        TDNS_KEEPALIVED=1
      else
        TDNS_KEEPALIVED=0
      fi
    fi

    if [[ "$TDNS_KEEPALIVED" == "1" ]]; then
      TDNS_VIP_CIDR="${TDNS_VIP_CIDR:-$(input_box "FLOATING DNS ADDRESS" "VIP with prefix length, for example 192.168.1.53/24:" "")}"
      TDNS_KEEPALIVED_PRIORITY="${TDNS_KEEPALIVED_PRIORITY:-$(input_box "KEEPALIVED PRIORITY" "Priority from 1 to 254:" "100")}"
      TDNS_VRID="${TDNS_VRID:-$(input_box "VRRP ROUTER ID" "Virtual router ID shared by all members, from 1 to 255:" "51")}"
      TDNS_KEEPALIVED_PEERS="${TDNS_KEEPALIVED_PEERS:-$(input_box "UNICAST PEERS" "Comma-separated peer IPv4 addresses. Leave empty for multicast:" "")}"
      if [[ -z "${TDNS_KEEPALIVED_PASSWORD:-}" ]]; then
        TDNS_KEEPALIVED_PASSWORD="$(password_box "VRRP PASSWORD" "Shared VRRP password, 1-8 letters, numbers, dots, underscores, or dashes:")"
      fi
      if yes_no "START KEEPALIVED" "Enable keepalived now? For unicast, every existing member must already list this new node as a peer."; then
        TDNS_KEEPALIVED_ENABLE_NOW=1
      else
        TDNS_KEEPALIVED_ENABLE_NOW=0
      fi
    fi
  fi

  TDNS_ADMIN_USER="${TDNS_ADMIN_USER:-admin}"
  TDNS_PRIMARY_TOTP="${TDNS_PRIMARY_TOTP:-}"

  case "$TDNS_ROLE" in
  join)
    validate_ipv4 "${TDNS_PRIMARY_IP:-}" || {
      msg_error "TDNS_PRIMARY_IP must be an IPv4 address"
      exit 1
    }
    [[ -n "${TDNS_ADMIN_PASSWORD:-}" ]] || {
      msg_error "The existing cluster password is required when joining"
      exit 1
    }
    [[ "$TDNS_ADMIN_USER" == "admin" ]] || {
      msg_error "Cluster joining currently requires the shared admin account"
      exit 1
    }
    ;;
  primary)
    [[ "${TDNS_CLUSTER_DOMAIN:-}" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z0-9-]+$ ]] || {
      msg_error "TDNS_CLUSTER_DOMAIN must be a DNS domain"
      exit 1
    }
    ;;
  standalone) ;;
  *)
    msg_error "TDNS_ROLE must be join, primary, or standalone"
    exit 1
    ;;
  esac

  if [[ -z "${TDNS_ADMIN_PASSWORD:-}" ]]; then
    TDNS_ADMIN_PASSWORD="$(openssl rand -base64 32 | tr -d '\n')"
    TDNS_PASSWORD_GENERATED=1
  else
    TDNS_PASSWORD_GENERATED=0
  fi

  if [[ "${TDNS_KEEPALIVED:-0}" == "1" ]]; then
    validate_ipv4_cidr "${TDNS_VIP_CIDR:-}" || {
      msg_error "TDNS_VIP_CIDR must be an IPv4 interface such as 192.168.1.53/24"
      exit 1
    }
    if [[ ! "${TDNS_KEEPALIVED_PRIORITY:-}" =~ ^[0-9]+$ ]] ||
      ((TDNS_KEEPALIVED_PRIORITY < 1 || TDNS_KEEPALIVED_PRIORITY > 254)); then
      msg_error "TDNS_KEEPALIVED_PRIORITY must be between 1 and 254"
      exit 1
    fi
    if [[ ! "${TDNS_VRID:-}" =~ ^[0-9]+$ ]] ||
      ((TDNS_VRID < 1 || TDNS_VRID > 255)); then
      msg_error "TDNS_VRID must be between 1 and 255"
      exit 1
    fi
    [[ "${TDNS_KEEPALIVED_PASSWORD:-}" =~ ^[A-Za-z0-9_.-]{1,8}$ ]] || {
      msg_error "TDNS_KEEPALIVED_PASSWORD must contain 1-8 safe ASCII characters"
      exit 1
    }
    TDNS_KEEPALIVED_ENABLE_NOW="${TDNS_KEEPALIVED_ENABLE_NOW:-0}"
  fi
}

push_content() {
  local destination="$1" mode="$2" content="$3" temporary
  umask 077
  temporary="$(mktemp /run/technitium-cluster.XXXXXX)"
  printf '%s' "$content" >"$temporary"
  if ! pct push "$CTID" "$temporary" "$destination"; then
    rm -f "$temporary"
    return 1
  fi
  rm -f "$temporary"
  pct exec "$CTID" -- chmod "$mode" "$destination"
}

install_node_helper() {
  local helper
  helper="$(_cs_fetch_text "scripts/technitium-cluster-node")"
  [[ -n "$helper" ]] || {
    msg_error "Could not load scripts/technitium-cluster-node"
    exit 1
  }
  push_content /usr/local/sbin/technitium-cluster-node 0755 "$helper"
}

configure_admin_password() {
  pct exec "$CTID" -- mkdir -p /opt/technitium
  push_content /opt/technitium/admin-password 0600 "$TDNS_ADMIN_PASSWORD"
}

wait_for_technitium() {
  local attempt
  for attempt in {1..90}; do
    if pct exec "$CTID" -- curl -fsS --max-time 2 http://127.0.0.1:5380/api/status >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  msg_error "Technitium did not become ready"
  return 1
}

configure_cluster() {
  case "$TDNS_ROLE" in
  join)
    msg_info "Joining the Technitium cluster"
    pct exec "$CTID" -- env TDNS_PRIMARY_TOTP="$TDNS_PRIMARY_TOTP" \
      /usr/local/sbin/technitium-cluster-node join \
      --primary "$TDNS_PRIMARY_IP" \
      --secondary "$IP" \
      --username "$TDNS_ADMIN_USER"
    msg_ok "Joined the Technitium cluster"
    ;;
  primary)
    msg_info "Initializing the Technitium cluster"
    pct exec "$CTID" -- /usr/local/sbin/technitium-cluster-node init-primary \
      --domain "$TDNS_CLUSTER_DOMAIN" \
      --ip "$IP"
    msg_ok "Initialized the Technitium cluster"
    ;;
  standalone)
    msg_ok "Configured a standalone Technitium server"
    ;;
  esac
}

configure_keepalived() {
  [[ "${TDNS_KEEPALIVED:-0}" == "1" ]] || return 0

  validate_ipv4 "$IP" || {
    msg_error "Keepalived requires a static IPv4 address; detected '$IP'"
    exit 1
  }

  local peer peer_lines="" unicast_block="" router_id config
  IFS=',' read -ra peers <<<"${TDNS_KEEPALIVED_PEERS:-}"
  for peer in "${peers[@]}"; do
    peer="${peer//[[:space:]]/}"
    [[ -z "$peer" || "$peer" == "$IP" ]] && continue
    validate_ipv4 "$peer" || {
      msg_error "Invalid keepalived peer IPv4 address: $peer"
      exit 1
    }
    peer_lines+="    ${peer}"$'\n'
  done

  if [[ -n "$peer_lines" ]]; then
    unicast_block="  unicast_src_ip ${IP}
  unicast_peer {
${peer_lines}  }"
  fi

  router_id="TECHNITIUM_$(printf '%s' "$HN" | tr '[:lower:]' '[:upper:]' | tr '.-' '__' | tr -cd 'A-Z0-9_')"
  config="global_defs {
  router_id ${router_id}
  enable_script_security
}
vrrp_script check_technitium {
  script \"/usr/local/sbin/check-technitium\"
  interval 3
  fall 2
  rise 2
  timeout 2
  user root
}
vrrp_instance DNS_VIP {
  state BACKUP
  interface eth0
  virtual_router_id ${TDNS_VRID}
  priority ${TDNS_KEEPALIVED_PRIORITY}
  advert_int 1
${unicast_block}
  authentication {
    auth_type PASS
    auth_pass ${TDNS_KEEPALIVED_PASSWORD}
  }
  virtual_ipaddress {
    ${TDNS_VIP_CIDR} dev eth0
  }
  track_script {
    check_technitium
  }
}
"

  msg_info "Configuring keepalived"
  push_content /etc/keepalived/keepalived.conf 0600 "$config"
  pct exec "$CTID" -- keepalived -t -f /etc/keepalived/keepalived.conf
  if [[ "${TDNS_KEEPALIVED_ENABLE_NOW:-0}" == "1" ]]; then
    pct exec "$CTID" -- systemctl enable --now keepalived.service
    msg_ok "Configured and started keepalived"
  else
    pct exec "$CTID" -- systemctl disable --now keepalived.service >/dev/null 2>&1 || true
    msg_ok "Staged keepalived without starting it"
  fi
}

start
collect_tdns_settings

if [[ "${NET:-dhcp}" == "dhcp" ]]; then
  msg_warn "A DNS server should use a static address or a fixed DHCP reservation"
fi

build_container

IP="$(pct exec "$CTID" -- ip -4 -o addr show dev eth0 scope global |
  awk '{print $4}' | cut -d/ -f1 | head -n1)"
validate_ipv4 "$IP" || {
  msg_error "Could not determine the new container's IPv4 address"
  exit 1
}

msg_info "Configuring Technitium DNS Server"
install_node_helper
configure_admin_password
pct exec "$CTID" -- systemctl start technitium.service
wait_for_technitium
configure_cluster
wait_for_technitium
configure_keepalived
msg_ok "Configured Technitium DNS Server"

description

msg_ok "Completed successfully!\n"
echo -e "${INFO}${YW}Container:${CL} ${BGN}${CTID}${CL}"
echo -e "${INFO}${YW}DNS address:${CL} ${BGN}${IP}${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:5380/${CL}"
echo -e "${INFO}${YW}Admin password:${CL} ${BGN}pct exec ${CTID} -- cat /opt/technitium/admin-password${CL}"
if [[ "${TDNS_KEEPALIVED:-0}" == "1" && "${TDNS_KEEPALIVED_ENABLE_NOW:-0}" != "1" ]]; then
  echo -e "${INFO}${YW}After updating reciprocal unicast peers, start keepalived with:${CL}"
  echo -e "${TAB}${BGN}pct exec ${CTID} -- systemctl enable --now keepalived${CL}"
fi
