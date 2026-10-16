#!/bin/sh

set -u

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------

SCRIPT_VERSION="v0.3.0"

BASE_DIR="${HOME}/hermes-manager"
CONFIG_FILE="${BASE_DIR}/config.env"

CLI_COMMAND="daytona-hermes"
CLI_SCRIPT="${BASE_DIR}/install.sh"
CLI_RAW_URL="https://raw.githubusercontent.com/WhoisNeon/Daytona-Hermes/main/install.sh"

DOCKER_CONFIG_FILE="${HOME}/.docker/config.json"
DOCKER_CONFIG_BACKUP="${HOME}/.docker/config.json.hermes.bak"
DOCKER_PROXY_STATE="${BASE_DIR}/docker-proxy.state"

HERMES_DATA_DIR="/data/hermes"
NINEROUTER_DATA_DIR="${BASE_DIR}/9router-data"

HERMES_REPO_URL="https://github.com/lovexbytes/hermes-railway-template/archive/refs/heads/main.tar.gz"
HERMES_REPO_DIR="${BASE_DIR}/hermes-railway-template"

HERMES_CONTAINER="hermes"
NINEROUTER_CONTAINER="9router"
FREELLMAPI_CONTAINER="freellmapi"

NINEROUTER_IMAGE="decolua/9router:latest"
DEFAULT_NINEROUTER_PORT="20128"
DEFAULT_NINEROUTER_PASSWORD="123456"

FREELLMAPI_DATA_DIR="${BASE_DIR}/freellmapi-data"
FREELLMAPI_IMAGE="ghcr.io/tashfeenahmed/freellmapi:latest"
DEFAULT_FREELLMAPI_PORT="3001"

XRAY_DATA_DIR="${BASE_DIR}/xray-data"
XRAY_CONFIG_FILE="${XRAY_DATA_DIR}/config.json"
XRAY_LINK_FILE="${XRAY_DATA_DIR}/node.link"

XRAY_CONTAINER="xray"
XRAY_IMAGE="teddysun/xray:latest"

# Bind every interface so containers on the Docker bridge can reach the proxy;
# host tools keep talking to loopback.
XRAY_LISTEN="0.0.0.0"
XRAY_CLIENT_HOST="127.0.0.1"
XRAY_SOCKS_PORT="10808"
XRAY_HTTP_PORT="10809"

XRAY_PROXY_URL="http://${XRAY_CLIENT_HOST}:${XRAY_HTTP_PORT}"
XRAY_SOCKS_URL="socks5://${XRAY_CLIENT_HOST}:${XRAY_SOCKS_PORT}"
XRAY_NO_PROXY_LIST="localhost,127.0.0.1,::1,0.0.0.0"

XRAY_PROFILE_FILE="/etc/profile.d/hermes-xray-proxy.sh"
XRAY_ENVIRONMENT_FILE="/etc/environment"

XRAY_TEST_URL="https://www.google.com/generate_204"
XRAY_TEST_IP_URL="https://api.ipify.org"

mkdir -p "$BASE_DIR"
mkdir -p "$HERMES_DATA_DIR"
mkdir -p "$NINEROUTER_DATA_DIR"
mkdir -p "$FREELLMAPI_DATA_DIR"
mkdir -p "$XRAY_DATA_DIR"

# Runtime defaults, overwritten by load_config when a config file exists.
XRAY_NODE_LABEL=""
XRAY_PARSED_QUERY=""

# ------------------------------------------------------------------------------
# Screen & Terminal Helpers
# ------------------------------------------------------------------------------

clear_screen() {
    printf '\033[2J\033[H'
    clear 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# Colors
# ------------------------------------------------------------------------------

RED="$(printf '\033[0;31m')"
GREEN="$(printf '\033[0;32m')"
YELLOW="$(printf '\033[1;33m')"
BLUE="$(printf '\033[0;34m')"
CYAN="$(printf '\033[0;36m')"
BOLD="$(printf '\033[1m')"
DIM="$(printf '\033[2m')"
NC="$(printf '\033[0m')"

# ------------------------------------------------------------------------------
# Menu Engine
# ------------------------------------------------------------------------------

BOX_W=72
BOX_BAR=""
_bb_i=0
while [ "$_bb_i" -lt 74 ]; do
    BOX_BAR="${BOX_BAR}─"
    _bb_i=$((_bb_i + 1))
done

ok()   { printf '\n  %s[✓]%s %s\n' "$GREEN" "$NC" "$1"; }
info() { printf '  %s[*]%s %s\n' "$BLUE" "$NC" "$1"; }
warn() { printf '  %s[!]%s %s\n' "$YELLOW" "$NC" "$1"; }
fail() { printf '  %s[✗]%s %s\n' "$RED" "$NC" "$1"; }

screen_title() {
    printf '\n%s%s%s\n' "$BOLD$CYAN" "$1" "$NC"
    printf '%s%s%s\n' "$CYAN" "$BOX_BAR" "$NC"
}

section() {
    printf '\n  %s%s%s\n' "$BOLD$CYAN" "$1" "$NC"
}

box_top() {
    printf '%s╭%s╮%s\n' "$CYAN" "$BOX_BAR" "$NC"
}

box_bottom() {
    printf '%s╰%s╯%s\n' "$CYAN" "$BOX_BAR" "$NC"
}

box_blank() {
    printf '%s│%s %-*s %s│%s\n' "$CYAN" "$NC" "$BOX_W" "" "$CYAN" "$NC"
}

# box_text <color> <plain ascii text>
box_text() {
    _bt_pad=$((BOX_W - ${#2}))

    if [ "$_bt_pad" -lt 0 ]; then
        _bt_pad=0
    fi

    printf '%s│%s %s%s%s%*s %s│%s\n' \
        "$CYAN" "$NC" "$1" "$2" "$NC" "$_bt_pad" "" "$CYAN" "$NC"
}

box_title() {
    box_text "$BOLD$CYAN" "$1"
}

# box_kv <plain key> <plain value> <value color>
box_kv() {
    _bk_pad=$((BOX_W - ${#1} - ${#2}))

    if [ "$_bk_pad" -lt 0 ]; then
        _bk_pad=0
    fi

    printf '%s│%s %s%s%s%s%*s %s│%s\n' \
        "$CYAN" "$NC" "$1" "$3" "$2" "$NC" "$_bk_pad" "" "$CYAN" "$NC"
}

# menu_item <number> <label> [description]
menu_item() {
    if [ -n "${3:-}" ]; then
        printf '  %s%3s%s  %-38s %s%s%s\n' \
            "$CYAN" "$1" "$NC" "$2" "$DIM" "$3" "$NC"
    else
        printf '  %s%3s%s  %s\n' "$CYAN" "$1" "$NC" "$2"
    fi
}

prompt_read() {
    printf '\n  %s%s %s' "$BOLD" "$1" "$NC"
    read -r _pr_value
}

pause_menu() {
    printf '\n  %sPress Enter to continue...%s' "$DIM" "$NC"
    read -r _pause
}

confirm_yes() {
    printf '\n  %s%s%s [Y/n]: ' "$YELLOW" "$1" "$NC"
    read -r _confirm

    case "$_confirm" in
        ''|[Yy]*) return 0 ;;
        *)        return 1 ;;
    esac
}

confirm_no() {
    printf '\n  %s%s%s [y/N]: ' "$YELLOW" "$1" "$NC"
    read -r _confirm

    case "$_confirm" in
        [Yy]*) return 0 ;;
        *)     return 1 ;;
    esac
}

# ------------------------------------------------------------------------------
# Version
# ------------------------------------------------------------------------------

get_version() {
    if command -v git >/dev/null 2>&1 && git -C "$BASE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$BASE_DIR" describe --tags --always 2>/dev/null || printf '%s' "$SCRIPT_VERSION"
    else
        printf '%s' "$SCRIPT_VERSION"
    fi
}

# ------------------------------------------------------------------------------
# Secret Redaction
# ------------------------------------------------------------------------------

redact_secret() {
    value="$1"

    if [ -z "$value" ]; then
        printf 'Not set'
        return
    fi

    length="$(printf '%s' "$value" | wc -c | tr -d ' ')"

    if [ "$length" -le 8 ]; then
        printf '••••••••'
        return
    fi

    case "$value" in
        *:*)
            bot_id="${value%%:*}"
            secret="${value#*:}"
            secret_length="$(printf '%s' "$secret" | wc -c | tr -d ' ')"

            if [ "$secret_length" -gt 6 ]; then
                first="$(printf '%s' "$secret" | cut -c1-3)"
                last="$(printf '%s' "$secret" | tail -c 4)"

                printf '%s:%s••••••••••••••••••••••••••••%s' \
                    "$bot_id" "$first" "$last"
                return
            fi
            ;;
    esac

    first="$(printf '%s' "$value" | cut -c1-4)"
    last="$(printf '%s' "$value" | tail -c 5)"

    printf '%s•••••••••••••••••••••••••%s' \
        "$first" "$last"
}

# ------------------------------------------------------------------------------
# Daytona ID
# ------------------------------------------------------------------------------

get_daytona_id() {
    if [ -n "${DAYTONA_SANDBOX_ID:-}" ]; then
        printf '%s' "$DAYTONA_SANDBOX_ID"
        return
    fi

    if [ -n "${SANDBOX_ID:-}" ]; then
        printf '%s' "$SANDBOX_ID"
        return
    fi

    if [ -n "${WORKSPACE_ID:-}" ]; then
        printf '%s' "$WORKSPACE_ID"
        return
    fi

    if [ -f "${HOME}/.daytona/id" ]; then
        tr -d '[:space:]' < "${HOME}/.daytona/id"
        return
    fi

    if [ -f "/etc/machine-id" ]; then
        tr -d '[:space:]' < "/etc/machine-id"
        return
    fi

    hostname
}

# ------------------------------------------------------------------------------
# Config
# ------------------------------------------------------------------------------

load_config() {
    HERMES_API_URL=""
    HERMES_API_TOKEN=""
    TELEGRAM_BOT_TOKEN=""
    TELEGRAM_ALLOWED_USERS=""
    HERMES_MODEL="mimo-v2.5-free"
    NINEROUTER_PORT="$DEFAULT_NINEROUTER_PORT"
    NINEROUTER_PASSWORD="$DEFAULT_NINEROUTER_PASSWORD"
    FREELLMAPI_PORT="$DEFAULT_FREELLMAPI_PORT"
    FREELLMAPI_ENCRYPTION_KEY=""
    XRAY_NODE_LABEL=""

    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        . "$CONFIG_FILE"
    fi
}

save_config() {
    umask 077

    cat > "$CONFIG_FILE" <<EOF
HERMES_API_URL="${HERMES_API_URL}"
HERMES_API_TOKEN="${HERMES_API_TOKEN}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_ALLOWED_USERS="${TELEGRAM_ALLOWED_USERS}"
HERMES_MODEL="${HERMES_MODEL}"
NINEROUTER_PORT="${NINEROUTER_PORT}"
NINEROUTER_PASSWORD="${NINEROUTER_PASSWORD}"
FREELLMAPI_PORT="${FREELLMAPI_PORT}"
FREELLMAPI_ENCRYPTION_KEY="${FREELLMAPI_ENCRYPTION_KEY}"
XRAY_NODE_LABEL="${XRAY_NODE_LABEL}"
EOF

    chmod 600 "$CONFIG_FILE"
}

# ------------------------------------------------------------------------------
# Docker
# ------------------------------------------------------------------------------

docker_available() {
    command -v docker >/dev/null 2>&1
}

docker_ready() {
    docker info >/dev/null 2>&1
}

ensure_docker() {
    if ! docker_available; then
        printf '%s[✗] Docker CLI is not available.%s\n' "$RED" "$NC"
        return 1
    fi

    if docker_ready; then
        return 0
    fi

    printf '%s[!] Docker daemon is not running.%s\n' "$YELLOW" "$NC"
    printf '%s[*] Attempting to start dockerd...%s\n' "$BLUE" "$NC"

    if ! command -v dockerd >/dev/null 2>&1; then
        printf '%s[✗] dockerd is not available.%s\n' "$RED" "$NC"
        return 1
    fi

    if [ ! -f /tmp/dockerd.log ]; then
        dockerd > /tmp/dockerd.log 2>&1 &
    fi

    attempt=0

    while [ "$attempt" -lt 30 ]; do
        if docker_ready; then
            printf '%s[✓] Docker daemon is ready.%s\n' "$GREEN" "$NC"
            return 0
        fi

        sleep 1
        attempt=$((attempt + 1))
    done

    printf '%s[✗] Docker daemon failed to start.%s\n' "$RED" "$NC"

    if [ -f /tmp/dockerd.log ]; then
        printf '\n%sLast Docker daemon logs:%s\n' "$YELLOW" "$NC"
        tail -30 /tmp/dockerd.log
    fi

    return 1
}

container_exists() {
    docker ps -a --format '{{.Names}}' 2>/dev/null |
        grep -Fxq "$1"
}

container_running() {
    docker ps --format '{{.Names}}' 2>/dev/null |
        grep -Fxq "$1"
}

get_container_ip() {
    docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# Component State
# ------------------------------------------------------------------------------

container_state() {
    if container_running "$1"; then
        printf 'running'
    elif container_exists "$1"; then
        printf 'stopped'
    else
        printf 'not installed'
    fi
}

state_color() {
    case "$1" in
        running) printf '%s' "$GREEN" ;;
        stopped) printf '%s' "$YELLOW" ;;
        *)       printf '%s' "$RED" ;;
    esac
}

# ------------------------------------------------------------------------------
# CLI Command (daytona-hermes)
# ------------------------------------------------------------------------------

SCRIPT_SOURCE=""

if [ -f "$0" ]; then
    SCRIPT_SOURCE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
fi

install_cli_command() {
    if [ -n "$SCRIPT_SOURCE" ] && [ -f "$SCRIPT_SOURCE" ]; then
        mkdir -p "$BASE_DIR" 2>/dev/null || true
        cp "$SCRIPT_SOURCE" "$CLI_SCRIPT" 2>/dev/null || true
    fi

    if [ ! -f "$CLI_SCRIPT" ]; then
        return 1
    fi

    chmod +x "$CLI_SCRIPT" 2>/dev/null || true

    _ic_first="$(printf '%s' "${PATH:-}" | cut -d: -f1)"

    for _ic_dir in /usr/local/bin "${HOME}/.local/bin" "$_ic_first"; do
        [ -n "$_ic_dir" ] || continue
        mkdir -p "$_ic_dir" 2>/dev/null || continue
        [ -w "$_ic_dir" ] || continue

        if ln -sf "$CLI_SCRIPT" "${_ic_dir}/${CLI_COMMAND}" 2>/dev/null; then
            return 0
        fi
    done

    return 1
}

cli_command_path() {
    command -v "$CLI_COMMAND" 2>/dev/null || true
}

update_manager() {
    if ! command -v wget >/dev/null 2>&1; then
        fail "wget is not available."
        return 1
    fi

    info "Downloading the latest manager..."

    if ! wget -q -O "${CLI_SCRIPT}.new" "$CLI_RAW_URL" ||
       [ ! -s "${CLI_SCRIPT}.new" ]; then

        rm -f "${CLI_SCRIPT}.new"
        fail "Download failed."
        return 1
    fi

    mv "${CLI_SCRIPT}.new" "$CLI_SCRIPT"
    chmod +x "$CLI_SCRIPT" 2>/dev/null || true
    install_cli_command >/dev/null 2>&1 || true

    ok "Manager updated. Restart '${CLI_COMMAND}' to use the new version."
}

# ------------------------------------------------------------------------------
# Docker Client Proxy (containers)
# ------------------------------------------------------------------------------
#
# ~/.docker/config.json makes the Docker CLI inject http(s)_proxy into every
# container it creates, so traffic from newly created containers goes through
# the local Xray proxy.

docker_bridge_gateway() {
    _dg_gw="$(docker network inspect bridge \
        --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)"

    if [ -n "$_dg_gw" ]; then
        printf '%s' "$_dg_gw"
        return 0
    fi

    printf '172.17.0.1'
}

docker_proxy_url() {
    printf 'http://%s:%s' "$(docker_bridge_gateway)" "$XRAY_HTTP_PORT"
}

docker_proxy_enabled() {
    [ -f "$DOCKER_PROXY_STATE" ]
}

enable_docker_proxy() {
    if ! docker_ready; then
        warn "Docker daemon is not available; skipping the Docker proxy setup."
        return 1
    fi

    _dp_url="$(docker_proxy_url)"
    mkdir -p "$(dirname "$DOCKER_CONFIG_FILE")" 2>/dev/null || true

    # Keep the user's existing config around so disabling restores it.
    if [ ! -f "$DOCKER_PROXY_STATE" ] && [ -f "$DOCKER_CONFIG_FILE" ]; then
        cp "$DOCKER_CONFIG_FILE" "$DOCKER_CONFIG_BACKUP" 2>/dev/null || true
    fi

    if command -v jq >/dev/null 2>&1 && [ -f "$DOCKER_CONFIG_FILE" ]; then
        _dp_tmp="${DOCKER_CONFIG_FILE}.hermes.$$"

        if jq --arg p "$_dp_url" --arg np "$XRAY_NO_PROXY_LIST" \
            '.proxies.default = {"httpProxy": $p, "httpsProxy": $p, "noProxy": $np}' \
            "$DOCKER_CONFIG_FILE" > "$_dp_tmp" 2>/dev/null; then

            mv "$_dp_tmp" "$DOCKER_CONFIG_FILE"
        else
            rm -f "$_dp_tmp"
        fi
    elif command -v python3 >/dev/null 2>&1 && [ -f "$DOCKER_CONFIG_FILE" ]; then
        python3 - "$DOCKER_CONFIG_FILE" "$_dp_url" "$XRAY_NO_PROXY_LIST" <<'PY' 2>/dev/null || true
import json, sys
path, proxy, noproxy = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}
data.setdefault("proxies", {})["default"] = {
    "httpProxy": proxy,
    "httpsProxy": proxy,
    "noProxy": noproxy,
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
    fi

    if ! grep -qF "$_dp_url" "$DOCKER_CONFIG_FILE" 2>/dev/null; then
        cat > "$DOCKER_CONFIG_FILE" <<EOF
{
  "proxies": {
    "default": {
      "httpProxy": "${_dp_url}",
      "httpsProxy": "${_dp_url}",
      "noProxy": "${XRAY_NO_PROXY_LIST}"
    }
  }
}
EOF
    fi

    printf '%s\n' "$_dp_url" > "$DOCKER_PROXY_STATE"
    return 0
}

disable_docker_proxy() {
    if [ -f "$DOCKER_CONFIG_BACKUP" ]; then
        mv -f "$DOCKER_CONFIG_BACKUP" "$DOCKER_CONFIG_FILE" 2>/dev/null || true
    elif [ -f "$DOCKER_CONFIG_FILE" ]; then
        # Keep the file when it holds settings that are not ours.
        if grep -q '"auths"' "$DOCKER_CONFIG_FILE" 2>/dev/null; then
            warn "Left $DOCKER_CONFIG_FILE in place (it has other settings); remove the proxies block manually."
        else
            rm -f "$DOCKER_CONFIG_FILE" 2>/dev/null || true
        fi
    fi

    rm -f "$DOCKER_PROXY_STATE" 2>/dev/null || true
    return 0
}

# ------------------------------------------------------------------------------
# Dashboard
# ------------------------------------------------------------------------------

render_dashboard() {
    load_config

    box_top
    box_title "HERMES  -  Daytona Sandbox Edition"
    box_text "$DIM" "Hermes | 9Router | FreeLLMAPI | Xray            WhoisNeon | $(get_version)"
    box_blank

    _rd_state="$(container_state "$HERMES_CONTAINER")"
    box_kv "  Hermes        " "$_rd_state" "$(state_color "$_rd_state")"

    _rd_state="$(container_state "$NINEROUTER_CONTAINER")"
    box_kv "  9Router       " "$_rd_state" "$(state_color "$_rd_state")"

    _rd_state="$(container_state "$FREELLMAPI_CONTAINER")"
    box_kv "  FreeLLMAPI    " "$_rd_state" "$(state_color "$_rd_state")"

    _rd_state="$(container_state "$XRAY_CONTAINER")"
    box_kv "  Xray core     " "$_rd_state" "$(state_color "$_rd_state")"

    if xray_proxy_enabled; then
        box_kv "  System proxy  " "enabled" "$GREEN"
    else
        box_kv "  System proxy  " "disabled" "$YELLOW"
    fi

    if docker_proxy_enabled; then
        box_kv "  Docker proxy  " "enabled" "$GREEN"
    else
        box_kv "  Docker proxy  " "disabled" "$YELLOW"
    fi

    box_bottom
    printf '\n'
}

# ------------------------------------------------------------------------------
# Download helper
# ------------------------------------------------------------------------------

download_file() {
    url="$1"
    output="$2"

    if ! command -v wget >/dev/null 2>&1; then
        printf '%s[✗] wget is not available.%s\n' "$RED" "$NC"
        return 1
    fi

    wget -q -O "$output" "$url"
}

# ------------------------------------------------------------------------------
# Hermes Template
# ------------------------------------------------------------------------------

prepare_hermes_source() {
    archive="/tmp/hermes-template.tar.gz"

    printf '%s[*] Downloading Hermes template...%s\n' "$BLUE" "$NC"

    rm -f "$archive"
    rm -rf "$HERMES_REPO_DIR"

    mkdir -p "$HERMES_REPO_DIR"

    if ! download_file "$HERMES_REPO_URL" "$archive"; then
        printf '%s[✗] Failed to download Hermes template.%s\n' \
            "$RED" "$NC"
        return 1
    fi

    printf '%s[*] Extracting Hermes template...%s\n' "$BLUE" "$NC"

    if ! tar -xzf "$archive" \
        --strip-components=1 \
        -C "$HERMES_REPO_DIR"; then

        printf '%s[✗] Failed to extract Hermes template.%s\n' \
            "$RED" "$NC"

        rm -f "$archive"
        return 1
    fi

    rm -f "$archive"

    return 0
}

# ------------------------------------------------------------------------------
# Hermes .env
# ------------------------------------------------------------------------------

write_hermes_env() {
    umask 077

    cat > "${HERMES_REPO_DIR}/.env" <<EOF
OPENAI_BASE_URL=${HERMES_API_URL}
OPENAI_API_KEY=${HERMES_API_TOKEN}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS}
HERMES_IMAGE_VERSION=latest
EOF

    chmod 600 "${HERMES_REPO_DIR}/.env"
}

# ------------------------------------------------------------------------------
# Hermes Install / Update
# ------------------------------------------------------------------------------

hermes_build_image() {
    if ! prepare_hermes_source; then
        return 1
    fi

    write_hermes_env

    cd "$HERMES_REPO_DIR" || return 1

    if [ ! -f Dockerfile ]; then
        fail "The Hermes template does not contain a Dockerfile."
        return 1
    fi

    info "Building the Hermes image..."

    if ! docker build \
        --build-arg HERMES_IMAGE_VERSION=latest \
        -t hermes-agent:latest .; then

        fail "Hermes Docker build failed."
        return 1
    fi

    return 0
}

hermes_run_container() {
    info "Starting Hermes..."

    if ! docker run -d \
        --name "$HERMES_CONTAINER" \
        --restart unless-stopped \
        --env-file "${HERMES_REPO_DIR}/.env" \
        -v "${HERMES_DATA_DIR}:/data" \
        hermes-agent:latest >/dev/null; then

        fail "Failed to start Hermes."
        return 1
    fi

    sleep 4

    if ! container_running "$HERMES_CONTAINER"; then
        fail "Hermes stopped after startup."
        printf '\n%sHermes logs:%s\n' "$YELLOW" "$NC"
        docker logs --tail 50 "$HERMES_CONTAINER" 2>&1 || true
        return 1
    fi

    configure_hermes_inside_container
    return 0
}

hermes_deploy() {
    if container_exists "$HERMES_CONTAINER"; then
        docker rm -f "$HERMES_CONTAINER" >/dev/null 2>&1 || true
    fi

    if ! hermes_build_image; then
        return 1
    fi

    if ! hermes_run_container; then
        return 1
    fi

    return 0
}

install_hermes() {
    clear_screen
    screen_title "Hermes · Install / Rebuild"

    if ! ensure_docker; then
        return
    fi

    load_config

    if container_exists "$HERMES_CONTAINER"; then
        if ! confirm_yes "Hermes already exists. Rebuild it? Data in ${HERMES_DATA_DIR} is kept."; then
            warn "Cancelled."
            return
        fi
    fi

    if hermes_deploy; then
        ok "Hermes is installed and running."
    fi
}

update_hermes() {
    clear_screen
    screen_title "Hermes · Update"

    if ! ensure_docker; then
        return
    fi

    load_config

    if ! container_exists "$HERMES_CONTAINER"; then
        warn "Hermes is not installed yet."
        return
    fi

    info "Re-downloading the template and rebuilding the image..."

    if hermes_deploy; then
        ok "Hermes is updated and running."
    fi
}

uninstall_hermes() {
    clear_screen
    screen_title "Hermes · Uninstall"

    if ! ensure_docker; then
        return
    fi

    if container_exists "$HERMES_CONTAINER"; then
        if confirm_yes "Remove the Hermes container?"; then
            docker rm -f "$HERMES_CONTAINER" >/dev/null 2>&1 || true
            ok "Hermes container removed."
        else
            warn "Cancelled."
            return
        fi
    else
        warn "Hermes is not installed."
    fi

    if [ -d "$HERMES_DATA_DIR" ]; then
        if confirm_no "Delete Hermes data (${HERMES_DATA_DIR})? This erases agent memory and skills."; then
            rm -rf "$HERMES_DATA_DIR"
            ok "Hermes data deleted."
        else
            info "Data kept at ${HERMES_DATA_DIR}."
        fi
    fi

    if confirm_no "Remove the Hermes image and the downloaded template?"; then
        docker rmi hermes-agent:latest >/dev/null 2>&1 || true
        rm -rf "$HERMES_REPO_DIR"
        ok "Image and template removed."
    fi
}

hermes_menu() {
    while true; do
        clear_screen
        load_config

        screen_title "Hermes"

        _hm_state="$(container_state "$HERMES_CONTAINER")"

        box_top
        box_kv "  Status        " "$_hm_state" "$(state_color "$_hm_state")"
        box_text "$DIM" "  API           ${HERMES_API_URL:-not set}"
        box_text "$DIM" "  Model         ${HERMES_MODEL}"
        box_bottom

        printf '\n'
        menu_item 1 "Install / Rebuild" "download template, build image"
        menu_item 2 "Update" "rebuild with the latest template"
        menu_item 3 "Configure API endpoint & token"
        menu_item 4 "Restart"
        menu_item 5 "Stop"
        menu_item 6 "Start"
        menu_item 7 "Logs"
        menu_item 8 "Shell"
        menu_item 9 "Uninstall"

        printf '\n'
        menu_item 0 "Back"

        printf '\n  Select [0-9]: '
        read -r _hm_choice

        case "$_hm_choice" in
            1) install_hermes ;;
            2) update_hermes ;;
            3) set_hermes_api ;;
            4) service_restart "$HERMES_CONTAINER" ;;
            5) service_stop "$HERMES_CONTAINER" ;;
            6) service_start "$HERMES_CONTAINER" ;;
            7) show_logs_for "$HERMES_CONTAINER" ;;
            8) shell_into "$HERMES_CONTAINER" ;;
            9) uninstall_hermes ;;
            0) return ;;
            *) fail "Invalid option." ;;
        esac

        pause_menu
    done
}

# ------------------------------------------------------------------------------
# Configure Hermes
# ------------------------------------------------------------------------------

configure_hermes_inside_container() {
    if ! container_running "$HERMES_CONTAINER"; then
        return
    fi

    if [ -z "$HERMES_API_URL" ] || [ -z "$HERMES_API_TOKEN" ]; then
        return
    fi

    printf '%s[*] Applying Hermes model configuration...%s\n' \
        "$BLUE" "$NC"

    docker exec "$HERMES_CONTAINER" \
        hermes config set model.provider custom \
        >/dev/null 2>&1 || true

    docker exec "$HERMES_CONTAINER" \
        hermes config set model.base_url "$HERMES_API_URL" \
        >/dev/null 2>&1 || true

    docker exec "$HERMES_CONTAINER" \
        hermes config set model.api_key "$HERMES_API_TOKEN" \
        >/dev/null 2>&1 || true

    docker exec "$HERMES_CONTAINER" \
        hermes config set env.OPENAI_BASE_URL "$HERMES_API_URL" \
        >/dev/null 2>&1 || true

    docker exec "$HERMES_CONTAINER" \
        hermes config set env.OPENAI_API_KEY "$HERMES_API_TOKEN" \
        >/dev/null 2>&1 || true

    docker exec "$HERMES_CONTAINER" \
        hermes config set model.default "$HERMES_MODEL" \
        >/dev/null 2>&1 || true
}

# ------------------------------------------------------------------------------
# 9Router
# ------------------------------------------------------------------------------

ninrouter_configure() {
    printf '\n  Port [%s]: ' "$NINEROUTER_PORT"
    read -r _nr_port

    if [ -n "$_nr_port" ]; then
        NINEROUTER_PORT="$_nr_port"
    fi

    case "$NINEROUTER_PORT" in
        ''|*[!0-9]*)
            fail "Invalid port."
            return 1
            ;;
    esac

    if [ "$NINEROUTER_PORT" -lt 1 ] || [ "$NINEROUTER_PORT" -gt 65535 ]; then
        fail "Port must be between 1 and 65535."
        return 1
    fi

    printf '  Password [%s]: ' "$NINEROUTER_PASSWORD"
    read -r _nr_password

    if [ -n "$_nr_password" ]; then
        NINEROUTER_PASSWORD="$_nr_password"
    fi

    save_config
    return 0
}

print_router_urls() {
    _nr_id="$(get_daytona_id)"
    _nr_ip="$(get_container_ip "$NINEROUTER_CONTAINER")"
    _nr_host="${_nr_ip:-localhost}"

    printf '\n  Dashboard      %shttp://%s:%s%s\n' \
        "$CYAN" "$_nr_host" "$NINEROUTER_PORT" "$NC"
    printf '  Public         %shttps://%s-%s.proxy.daytona.work%s\n' \
        "$CYAN" "$NINEROUTER_PORT" "$_nr_id" "$NC"
    printf '  OpenAI API     %shttp://%s:%s/v1%s\n' \
        "$CYAN" "$_nr_host" "$NINEROUTER_PORT" "$NC"
    printf '                 %shttps://%s-%s.proxy.daytona.work/v1%s\n' \
        "$CYAN" "$NINEROUTER_PORT" "$_nr_id" "$NC"
}

ninrouter_run() {
    info "Pulling the 9Router image..."

    if ! docker pull "$NINEROUTER_IMAGE"; then
        fail "Failed to pull the 9Router image."
        return 1
    fi

    info "Starting 9Router..."

    if ! docker run -d \
        --name "$NINEROUTER_CONTAINER" \
        --restart unless-stopped \
        -p "${NINEROUTER_PORT}:20128" \
        -v "${NINEROUTER_DATA_DIR}:/app/data" \
        -e DATA_DIR=/app/data \
        -e PORT=20128 \
        -e HOSTNAME=0.0.0.0 \
        -e INITIAL_PASSWORD="$NINEROUTER_PASSWORD" \
        "$NINEROUTER_IMAGE" >/dev/null; then

        fail "Failed to start 9Router."
        return 1
    fi

    sleep 4

    if ! container_running "$NINEROUTER_CONTAINER"; then
        fail "9Router stopped after startup."
        docker logs --tail 50 "$NINEROUTER_CONTAINER" 2>&1 || true
        return 1
    fi

    print_router_urls
    return 0
}

install_9router() {
    clear_screen
    screen_title "9Router · Install / Reconfigure"

    if ! ensure_docker; then
        return
    fi

    load_config

    if container_exists "$NINEROUTER_CONTAINER"; then
        if ! confirm_yes "9Router already exists. Reinstall it? Data in ${NINEROUTER_DATA_DIR} is kept."; then
            warn "Cancelled."
            return
        fi

        docker rm -f "$NINEROUTER_CONTAINER" >/dev/null 2>&1 || true
    fi

    if ! ninrouter_configure; then
        return
    fi

    if ninrouter_run; then
        ok "9Router is running."
    fi
}

update_9router() {
    clear_screen
    screen_title "9Router · Update"

    if ! ensure_docker; then
        return
    fi

    load_config

    if ! container_exists "$NINEROUTER_CONTAINER"; then
        warn "9Router is not installed yet."
        return
    fi

    docker rm -f "$NINEROUTER_CONTAINER" >/dev/null 2>&1 || true

    if ninrouter_run; then
        ok "9Router is updated to the latest image."
    fi
}

uninstall_9router() {
    clear_screen
    screen_title "9Router · Uninstall"

    if ! ensure_docker; then
        return
    fi

    if container_exists "$NINEROUTER_CONTAINER"; then
        if confirm_yes "Remove the 9Router container?"; then
            docker rm -f "$NINEROUTER_CONTAINER" >/dev/null 2>&1 || true
            ok "9Router container removed."
        else
            warn "Cancelled."
            return
        fi
    else
        warn "9Router is not installed."
    fi

    if [ -d "$NINEROUTER_DATA_DIR" ]; then
        if confirm_no "Delete 9Router data (${NINEROUTER_DATA_DIR})?"; then
            rm -rf "$NINEROUTER_DATA_DIR"
            ok "9Router data deleted."
        else
            info "Data kept at ${NINEROUTER_DATA_DIR}."
        fi
    fi

    if confirm_no "Remove the 9Router image?"; then
        docker rmi "$NINEROUTER_IMAGE" >/dev/null 2>&1 || true
        ok "Image removed."
    fi
}

ninrouter_menu() {
    while true; do
        clear_screen
        load_config

        screen_title "9Router"

        _nr_state="$(container_state "$NINEROUTER_CONTAINER")"
        _nr_ip="$(get_container_ip "$NINEROUTER_CONTAINER")"

        box_top
        box_kv "  Status        " "$_nr_state" "$(state_color "$_nr_state")"
        box_text "$DIM" "  Port          ${NINEROUTER_PORT}"

        if [ -n "$_nr_ip" ]; then
            box_text "$DIM" "  Local         http://${_nr_ip}:${NINEROUTER_PORT}"
        fi

        box_bottom

        printf '\n'
        menu_item 1 "Install / Reconfigure" "port, password"
        menu_item 2 "Update" "pull the latest image, keep data"
        menu_item 3 "Restart"
        menu_item 4 "Stop"
        menu_item 5 "Start"
        menu_item 6 "Logs"
        menu_item 7 "Shell"
        menu_item 8 "Uninstall"

        printf '\n'
        menu_item 0 "Back"

        printf '\n  Select [0-8]: '
        read -r _nr_choice

        case "$_nr_choice" in
            1) install_9router ;;
            2) update_9router ;;
            3) service_restart "$NINEROUTER_CONTAINER" ;;
            4) service_stop "$NINEROUTER_CONTAINER" ;;
            5) service_start "$NINEROUTER_CONTAINER" ;;
            6) show_logs_for "$NINEROUTER_CONTAINER" ;;
            7) shell_into "$NINEROUTER_CONTAINER" ;;
            8) uninstall_9router ;;
            0) return ;;
            *) fail "Invalid option." ;;
        esac

        pause_menu
    done
}

# ------------------------------------------------------------------------------
# FreeLLMAPI
# ------------------------------------------------------------------------------

generate_encryption_key() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32
        return
    fi

    if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
        od -An -N32 -tx1 /dev/urandom | tr -d ' \n'
        return
    fi

    return 1
}

ensure_freellmapi_encryption_key() {
    if [ -n "$FREELLMAPI_ENCRYPTION_KEY" ]; then
        return 0
    fi

    FREELLMAPI_ENCRYPTION_KEY="$(generate_encryption_key)" || true

    if [ -z "$FREELLMAPI_ENCRYPTION_KEY" ]; then
        printf '%s[✗] Could not generate an encryption key (need openssl or od + /dev/urandom).%s\n' \
            "$RED" "$NC"
        return 1
    fi

    save_config
    return 0
}

freellmapi_configure() {
    printf '\n  Port [%s]: ' "$FREELLMAPI_PORT"
    read -r _fl_port

    if [ -n "$_fl_port" ]; then
        FREELLMAPI_PORT="$_fl_port"
    fi

    case "$FREELLMAPI_PORT" in
        ''|*[!0-9]*)
            fail "Invalid port."
            return 1
            ;;
    esac

    if [ "$FREELLMAPI_PORT" -lt 1 ] || [ "$FREELLMAPI_PORT" -gt 65535 ]; then
        fail "Port must be between 1 and 65535."
        return 1
    fi

    if ! ensure_freellmapi_encryption_key; then
        return 1
    fi

    save_config
    return 0
}

print_freellmapi_urls() {
    _fl_id="$(get_daytona_id)"
    _fl_ip="$(get_container_ip "$FREELLMAPI_CONTAINER")"
    _fl_host="${_fl_ip:-localhost}"

    printf '\n  Dashboard      %shttp://%s:%s%s\n' \
        "$CYAN" "$_fl_host" "$FREELLMAPI_PORT" "$NC"
    printf '  Public         %shttps://%s-%s.proxy.daytona.work%s\n' \
        "$CYAN" "$FREELLMAPI_PORT" "$_fl_id" "$NC"
    printf '  OpenAI API     %shttp://%s:%s/v1%s\n' \
        "$CYAN" "$_fl_host" "$FREELLMAPI_PORT" "$NC"
    printf '                 %shttps://%s-%s.proxy.daytona.work/v1%s\n' \
        "$CYAN" "$FREELLMAPI_PORT" "$_fl_id" "$NC"
}

freellmapi_run() {
    info "Pulling the FreeLLMAPI image..."

    if ! docker pull "$FREELLMAPI_IMAGE"; then
        fail "Failed to pull the FreeLLMAPI image."
        return 1
    fi

    info "Starting FreeLLMAPI..."

    if ! docker run -d \
        --name "$FREELLMAPI_CONTAINER" \
        --restart unless-stopped \
        -p "${FREELLMAPI_PORT}:3001" \
        -v "${FREELLMAPI_DATA_DIR}:/app/server/data" \
        -e NODE_ENV=production \
        -e PORT=3001 \
        -e HOST_BIND=0.0.0.0 \
        -e ENCRYPTION_KEY="$FREELLMAPI_ENCRYPTION_KEY" \
        "$FREELLMAPI_IMAGE" >/dev/null; then

        fail "Failed to start FreeLLMAPI."
        return 1
    fi

    sleep 6

    if ! container_running "$FREELLMAPI_CONTAINER"; then
        fail "FreeLLMAPI stopped after startup."
        docker logs --tail 50 "$FREELLMAPI_CONTAINER" 2>&1 || true
        return 1
    fi

    print_freellmapi_urls
    return 0
}

install_freellmapi() {
    clear_screen
    screen_title "FreeLLMAPI · Install / Reconfigure"

    if ! ensure_docker; then
        return
    fi

    load_config

    if container_exists "$FREELLMAPI_CONTAINER"; then
        if ! confirm_yes "FreeLLMAPI already exists. Reinstall it? Data in ${FREELLMAPI_DATA_DIR} is kept."; then
            warn "Cancelled."
            return
        fi

        docker rm -f "$FREELLMAPI_CONTAINER" >/dev/null 2>&1 || true
    fi

    if ! freellmapi_configure; then
        return
    fi

    if freellmapi_run; then
        ok "FreeLLMAPI is running."
        printf '  On first run, open the dashboard and create the admin\n'
        printf '  account (the setup code is printed in the container logs).\n'
    fi
}

update_freellmapi() {
    clear_screen
    screen_title "FreeLLMAPI · Update"

    if ! ensure_docker; then
        return
    fi

    load_config

    if ! container_exists "$FREELLMAPI_CONTAINER"; then
        warn "FreeLLMAPI is not installed yet."
        return
    fi

    docker rm -f "$FREELLMAPI_CONTAINER" >/dev/null 2>&1 || true

    if freellmapi_run; then
        ok "FreeLLMAPI is updated to the latest image."
    fi
}

uninstall_freellmapi() {
    clear_screen
    screen_title "FreeLLMAPI · Uninstall"

    if ! ensure_docker; then
        return
    fi

    if container_exists "$FREELLMAPI_CONTAINER"; then
        if confirm_yes "Remove the FreeLLMAPI container?"; then
            docker rm -f "$FREELLMAPI_CONTAINER" >/dev/null 2>&1 || true
            ok "FreeLLMAPI container removed."
        else
            warn "Cancelled."
            return
        fi
    else
        warn "FreeLLMAPI is not installed."
    fi

    if [ -d "$FREELLMAPI_DATA_DIR" ]; then
        if confirm_no "Delete FreeLLMAPI data (${FREELLMAPI_DATA_DIR})? This erases provider keys and settings."; then
            rm -rf "$FREELLMAPI_DATA_DIR"
            ok "FreeLLMAPI data deleted."
        else
            info "Data kept at ${FREELLMAPI_DATA_DIR}."
        fi
    fi

    if confirm_no "Remove the FreeLLMAPI image?"; then
        docker rmi "$FREELLMAPI_IMAGE" >/dev/null 2>&1 || true
        ok "Image removed."
    fi
}

freellmapi_menu() {
    while true; do
        clear_screen
        load_config

        screen_title "FreeLLMAPI"

        _fl_state="$(container_state "$FREELLMAPI_CONTAINER")"
        _fl_ip="$(get_container_ip "$FREELLMAPI_CONTAINER")"

        box_top
        box_kv "  Status        " "$_fl_state" "$(state_color "$_fl_state")"
        box_text "$DIM" "  Port          ${FREELLMAPI_PORT}"

        if [ -n "$_fl_ip" ]; then
            box_text "$DIM" "  Local         http://${_fl_ip}:${FREELLMAPI_PORT}"
        fi

        box_bottom

        printf '\n'
        menu_item 1 "Install / Reconfigure" "port, encryption key"
        menu_item 2 "Update" "pull the latest image, keep data"
        menu_item 3 "Restart"
        menu_item 4 "Stop"
        menu_item 5 "Start"
        menu_item 6 "Logs"
        menu_item 7 "Shell"
        menu_item 8 "Uninstall"

        printf '\n'
        menu_item 0 "Back"

        printf '\n  Select [0-8]: '
        read -r _fl_choice

        case "$_fl_choice" in
            1) install_freellmapi ;;
            2) update_freellmapi ;;
            3) service_restart "$FREELLMAPI_CONTAINER" ;;
            4) service_stop "$FREELLMAPI_CONTAINER" ;;
            5) service_start "$FREELLMAPI_CONTAINER" ;;
            6) show_logs_for "$FREELLMAPI_CONTAINER" ;;
            7) shell_into "$FREELLMAPI_CONTAINER" ;;
            8) uninstall_freellmapi ;;
            0) return ;;
            *) fail "Invalid option." ;;
        esac

        pause_menu
    done
}

# ------------------------------------------------------------------------------
# Hermes Container Lifecycle Helper
# ------------------------------------------------------------------------------

recreate_hermes_container() {
    if ! container_running "$HERMES_CONTAINER"; then
        return 0
    fi

    printf '%s[*] Recreating Hermes container with updated environment variables...%s\n' \
        "$BLUE" "$NC"

    docker rm -f "$HERMES_CONTAINER" >/dev/null 2>&1 || true

    if ! docker run -d \
        --name "$HERMES_CONTAINER" \
        --restart unless-stopped \
        --env-file "${HERMES_REPO_DIR}/.env" \
        -v "${HERMES_DATA_DIR}:/data" \
        hermes-agent:latest >/dev/null 2>&1; then

        printf '%s[✗] Failed to restart Hermes with new configuration.%s\n' "$RED" "$NC"
        return 1
    fi

    sleep 3
    configure_hermes_inside_container
    return 0
}

# ------------------------------------------------------------------------------
# Hermes API Settings
# ------------------------------------------------------------------------------

set_hermes_api() {
    clear_screen
    screen_title "Hermes API (Custom OpenAI-compatible endpoint)"

    load_config

    printf '\n  %sHermes will use the "custom" provider: any OpenAI-compatible%s\n' \
        "$DIM" "$NC"
    printf '  %sendpoint works (9Router, FreeLLMAPI, OpenAI, Ollama, ...).%s\n' \
        "$DIM" "$NC"

    printf 'Current endpoint:\n'
    printf '  %s%s%s\n\n' \
        "$CYAN" "${HERMES_API_URL:-Not set}" "$NC"

    printf 'New endpoint [Enter = keep current]: '
    read -r value

    if [ -n "$value" ]; then
        HERMES_API_URL="$value"
    fi

    printf '\nCurrent API token:\n'
    printf '  %s%s%s\n\n' \
        "$CYAN" "$(redact_secret "${HERMES_API_TOKEN:-}")" "$NC"

    printf 'New API token [Enter = keep current]: '
    read -r value

    if [ -n "$value" ]; then
        HERMES_API_TOKEN="$value"
    fi

    save_config
    write_hermes_env_if_exists
    recreate_hermes_container

    printf '\n%s[✓] Hermes API configuration saved and applied.%s\n' \
        "$GREEN" "$NC"
}

write_hermes_env_if_exists() {
    if [ ! -d "$HERMES_REPO_DIR" ]; then
        return
    fi

    write_hermes_env
}

# ------------------------------------------------------------------------------
# Telegram
# ------------------------------------------------------------------------------

set_telegram() {
    clear_screen
    printf '%s--- Hermes Telegram Configuration ---%s\n\n' \
        "$BOLD" "$NC"

    load_config

    printf 'Current bot token:\n'
    printf '  %s%s%s\n\n' \
        "$CYAN" "$(redact_secret "${TELEGRAM_BOT_TOKEN:-}")" "$NC"

    printf 'New bot token [Enter = keep current]: '
    read -r value

    if [ -n "$value" ]; then
        TELEGRAM_BOT_TOKEN="$value"
    fi

    printf '\nCurrent allowed users:\n'
    printf '  %s%s%s\n\n' \
        "$CYAN" "${TELEGRAM_ALLOWED_USERS:-Not set}" "$NC"

    printf 'Allowed user IDs, comma-separated [Enter = keep current]: '
    read -r value

    if [ -n "$value" ]; then
        TELEGRAM_ALLOWED_USERS="$value"
    fi

    save_config
    write_hermes_env_if_exists
    recreate_hermes_container

    printf '\n%s[✓] Telegram configuration saved and applied.%s\n' \
        "$GREEN" "$NC"
}

# ------------------------------------------------------------------------------
# Show Hermes Config
# ------------------------------------------------------------------------------

show_hermes_config() {
    clear_screen
    printf '%s================ Hermes Configuration ================%s\n\n' \
        "$BOLD" "$NC"

    load_config

    printf 'API endpoint:\n'
    printf '  %s%s%s\n\n' \
        "$CYAN" "${HERMES_API_URL:-Not set}" "$NC"

    printf 'API token:\n'
    printf '  %s%s%s\n\n' \
        "$CYAN" "$(redact_secret "${HERMES_API_TOKEN:-}")" "$NC"

    printf 'Telegram token:\n'
    printf '  %s%s%s\n\n' \
        "$CYAN" "$(redact_secret "${TELEGRAM_BOT_TOKEN:-}")" "$NC"

    printf 'Allowed users:\n'
    printf '  %s%s%s\n\n' \
        "$CYAN" "${TELEGRAM_ALLOWED_USERS:-Not set}" "$NC"

    printf 'Default model:\n'
    printf '  %s%s%s\n\n' \
        "$CYAN" "$HERMES_MODEL" "$NC"

    if container_running "$HERMES_CONTAINER"; then
        printf '%sContainer configuration:%s\n' "$BOLD" "$NC"

        docker exec "$HERMES_CONTAINER" \
            hermes config 2>/dev/null |
            grep -v -E 'api_key|token|secret' ||
            true
    else
        printf '%sHermes container is not running.%s\n' \
            "$YELLOW" "$NC"
    fi

    printf '\n%s======================================================%s\n' \
        "$BOLD" "$NC"
}

# ------------------------------------------------------------------------------
# Service Lifecycle & Shell
# ------------------------------------------------------------------------------

service_restart() {
    if ! ensure_docker; then
        return
    fi

    if ! container_exists "$1"; then
        warn "Container $1 does not exist."
        return
    fi

    if docker restart "$1" >/dev/null 2>&1; then
        ok "$1 restarted."
    else
        fail "Failed to restart $1."
    fi
}

service_stop() {
    if ! ensure_docker; then
        return
    fi

    if ! container_running "$1"; then
        warn "Container $1 is not running."
        return
    fi

    if docker stop "$1" >/dev/null 2>&1; then
        ok "$1 stopped."
    else
        fail "Failed to stop $1."
    fi
}

service_start() {
    if ! ensure_docker; then
        return
    fi

    if ! container_exists "$1"; then
        warn "Container $1 does not exist."
        return
    fi

    if docker start "$1" >/dev/null 2>&1; then
        ok "$1 started."
    else
        fail "Failed to start $1."
    fi
}

shell_into() {
    _si_container="$1"

    if ! container_running "$_si_container"; then
        fail "Container $_si_container is not running."
        return
    fi

    printf '\n  %sOpening a shell in %s. Type "exit" to return.%s\n\n' \
        "$CYAN" "$_si_container" "$NC"

    if docker exec "$_si_container" which bash >/dev/null 2>&1; then
        docker exec -it "$_si_container" bash
    else
        docker exec -it "$_si_container" sh
    fi
}

show_logs_for() {
    if ! ensure_docker; then
        return
    fi

    clear_screen
    screen_title "Logs · $1"
    printf '\n'

    if ! container_exists "$1"; then
        warn "Container $1 does not exist."
        return
    fi

    docker logs --tail 100 "$1" 2>&1
}

# ------------------------------------------------------------------------------
# Pick a Component
# ------------------------------------------------------------------------------

choose_container() {
    printf '\n'
    menu_item 1 "Hermes" "$(container_state "$HERMES_CONTAINER")"
    menu_item 2 "9Router" "$(container_state "$NINEROUTER_CONTAINER")"
    menu_item 3 "FreeLLMAPI" "$(container_state "$FREELLMAPI_CONTAINER")"
    menu_item 4 "Xray" "$(container_state "$XRAY_CONTAINER")"
    printf '\n'
    menu_item 0 "Cancel"

    printf '\n  Select [0-4]: '
    read -r _cc

    case "$_cc" in
        1) printf '%s' "$HERMES_CONTAINER" ;;
        2) printf '%s' "$NINEROUTER_CONTAINER" ;;
        3) printf '%s' "$FREELLMAPI_CONTAINER" ;;
        4) printf '%s' "$XRAY_CONTAINER" ;;
        *) printf '' ;;
    esac
}

show_logs() {
    clear_screen
    screen_title "Container Logs"

    _sl_container="$(choose_container)"
    [ -n "$_sl_container" ] || return

    show_logs_for "$_sl_container"
}

exec_in_container() {
    clear_screen
    screen_title "Shell into a Container"

    _ec_container="$(choose_container)"
    [ -n "$_ec_container" ] || return

    shell_into "$_ec_container"
}

# ------------------------------------------------------------------------------
# Xray Proxy
# ------------------------------------------------------------------------------
#
# Node links (vless://, vmess://, trojan://) are converted into a standard Xray
# client config.json exposing a local SOCKS (10808) and HTTP (10809) inbound.
# The core itself runs inside a Docker container sharing the host network, so the
# two local ports are reachable from the sandbox without any port publishing.

# ------------------------------------------------------------------------------
# Xray Parsing Helpers
# ------------------------------------------------------------------------------

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Percent-decode a URL component using only POSIX shell built-ins.
url_decode() {
    _ud_input="$1"
    _ud_output=""

    while [ -n "$_ud_input" ]; do
        case "$_ud_input" in
            *%*) ;;
            *) break ;;
        esac

        _ud_rest="${_ud_input#*%}"
        _ud_output="${_ud_output}${_ud_input%%"%"*}"
        _ud_input="$_ud_rest"

        if [ "${#_ud_input}" -lt 2 ]; then
            _ud_output="${_ud_output}%${_ud_input}"
            _ud_input=""
            break
        fi

        _ud_hex="${_ud_input%"${_ud_input#??}"}"
        _ud_input="${_ud_input#??}"

        case "$_ud_hex" in
            [0-9A-Fa-f][0-9A-Fa-f])
                _ud_output="${_ud_output}$(printf '%b' \
                    "\\$(printf '%03o' "$((0x$_ud_hex))")")"
                ;;
            *)
                _ud_output="${_ud_output}%${_ud_hex}"
                ;;
        esac
    done

    printf '%s' "${_ud_output}${_ud_input}"
}

# Look up a single key inside an already extracted "?a=1&b=2" query string.
url_get_param() {
    _ug_query="$1"
    _ug_key="$2"

    while [ -n "$_ug_query" ]; do
        case "$_ug_query" in
            *'&'*)
                _ug_pair="${_ug_query%%&*}"
                _ug_query="${_ug_query#*&}"
                ;;
            *)
                _ug_pair="$_ug_query"
                _ug_query=""
                ;;
        esac

        case "$_ug_pair" in
            "$_ug_key"=*)
                url_decode "${_ug_pair#"$_ug_key"=}"
                return 0
                ;;
        esac
    done

    return 1
}

# Pure shell Base64 decoder, used only when neither base64 nor openssl exist.
base64_decode_fallback() {
    _bf_input="$1"
    _bf_alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    _bf_bits=""
    _bf_index=0
    _bf_len="${#_bf_input}"

    while [ "$_bf_index" -lt "$_bf_len" ]; do
        _bf_char="${_bf_input%"${_bf_input#?}"}"
        _bf_input="${_bf_input#?}"
        _bf_index=$((_bf_index + 1))

        case "$_bf_char" in
            [A-Za-z0-9+/]) ;;
            *) continue ;;
        esac

        _bf_prefix="${_bf_alphabet%%"$_bf_char"*}"
        _bf_value="${#_bf_prefix}"

        _bf_bits="${_bf_bits}$(( (_bf_value >> 5) & 1 ))$(( (_bf_value >> 4) & 1 ))$(( (_bf_value >> 3) & 1 ))$(( (_bf_value >> 2) & 1 ))$(( (_bf_value >> 1) & 1 ))$(( _bf_value & 1 ))"

        while [ "${#_bf_bits}" -ge 8 ]; do
            _bf_byte=0
            _bf_bit=0

            while [ "$_bf_bit" -lt 8 ]; do
                _bf_byte=$(( _bf_byte * 2 + ${_bf_bits%"${_bf_bits#?}"} ))
                _bf_bits="${_bf_bits#?}"
                _bf_bit=$((_bf_bit + 1))
            done

            printf '%b' "\\$(printf '%03o' "$_bf_byte")"
        done
    done
}

base64_decode() {
    _bd_input="$(printf '%s' "$1" | tr -d '\n\r \t')"

    case "$_bd_input" in
        *=*) _bd_input="${_bd_input%%=*}" ;;
    esac

    if [ -z "$_bd_input" ]; then
        return 1
    fi

    if command -v base64 >/dev/null 2>&1; then
        _bd_out="$(printf '%s' "$_bd_input" | base64 -d 2>/dev/null || true)"

        if [ -n "$_bd_out" ]; then
            printf '%s' "$_bd_out"
            return 0
        fi
    fi

    if command -v openssl >/dev/null 2>&1; then
        _bd_out="$(printf '%s' "$_bd_input" |
            openssl base64 -d -A 2>/dev/null || true)"

        if [ -n "$_bd_out" ]; then
            printf '%s' "$_bd_out"
            return 0
        fi
    fi

    base64_decode_fallback "$_bd_input"
}

# Read a field out of the JSON payload carried by a vmess:// link.
xray_vmess_field() {
    _vf_raw="$1"
    _vf_key="$2"

    _vf_out="$(printf '%s' "$_vf_raw" | tr -d '\n' |
        sed -n "s/.*\"${_vf_key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" |
        sed -n 1p)"

    if [ -z "$_vf_out" ]; then
        _vf_out="$(printf '%s' "$_vf_raw" | tr -d '\n' |
            sed -n "s/.*\"${_vf_key}\"[[:space:]]*:[[:space:]]*\([0-9][0-9.]*\).*/\1/p" |
            sed -n 1p)"
    fi

    printf '%s' "$_vf_out"
}

xray_get_param() {
    printf '%s' "$(url_get_param "$XRAY_PARSED_QUERY" "$1" 2>/dev/null || true)"
}

# Split "host:port", "[v6::addr]:port" or a bare host into globals.
xray_parse_hostport() {
    case "$1" in
        \[*\]*)
            xray_address="${1%%\]*}"
            xray_address="${xray_address#\[}"
            xray_port="${1#*\]}"
            xray_port="${xray_port#:}"
            ;;
        *:*)
            xray_address="${1%:*}"
            xray_port="${1##*:}"
            ;;
        *)
            xray_address="$1"
            xray_port="443"
            ;;
    esac
}

# Render a comma separated list as a JSON string array, e.g. "h2,http/1.1".
xray_json_string_array() {
    _jsa_out=""
    _jsa_rest="$1"

    while [ -n "$_jsa_rest" ]; do
        case "$_jsa_rest" in
            *,*)
                _jsa_item="${_jsa_rest%%,*}"
                _jsa_rest="${_jsa_rest#*,}"
                ;;
            *)
                _jsa_item="$_jsa_rest"
                _jsa_rest=""
                ;;
        esac

        [ -z "$_jsa_item" ] && continue

        _jsa_item="\"$(json_escape "$_jsa_item")\""

        if [ -z "$_jsa_out" ]; then
            _jsa_out="$_jsa_item"
        else
            _jsa_out="${_jsa_out},${_jsa_item}"
        fi
    done

    if [ -z "$_jsa_out" ]; then
        printf '[]'
    else
        printf '[%s]' "$_jsa_out"
    fi
}

# ------------------------------------------------------------------------------
# Xray Link Parsing
# ------------------------------------------------------------------------------

xray_normalize_network() {
    case "$1" in
        ''|raw|tcp)      printf 'tcp' ;;
        ws|websocket)    printf 'ws' ;;
        grpc)            printf 'grpc' ;;
        httpupgrade)     printf 'httpupgrade' ;;
        xhttp|splithttp) printf 'xhttp' ;;
        kcp|mkcp)        printf 'kcp' ;;
        h2|http|quic)
            printf '%s[✗] The "%s" transport was removed from Xray. Use an xhttp, ws or tcp node instead.%s\n' \
                "$RED" "$1" "$NC" >&2
            return 1
            ;;
        *)               printf 'tcp' ;;
    esac
}

xray_normalize_header() {
    case "$1" in
        http) printf 'http' ;;
        *)    printf 'none' ;;
    esac
}

# vmess:// carries a Base64 encoded JSON document rather than a URL body.
xray_parse_vmess_link() {
    _pv_json="$(base64_decode "${1#vmess://}")"

    if [ -z "$_pv_json" ]; then
        printf '%s[✗] The vmess:// payload is not valid Base64 JSON.%s\n' \
            "$RED" "$NC"
        return 1
    fi

    xray_proto="vmess"
    xray_label="$(xray_vmess_field "$_pv_json" ps)"
    xray_address="$(xray_vmess_field "$_pv_json" add)"
    xray_port="$(xray_vmess_field "$_pv_json" port)"
    xray_id="$(xray_vmess_field "$_pv_json" id)"
    xray_scy="$(xray_vmess_field "$_pv_json" scy)"

    _pv_net="$(xray_vmess_field "$_pv_json" net)"
    _pv_header="$(xray_vmess_field "$_pv_json" type)"
    _pv_host="$(xray_vmess_field "$_pv_json" host)"
    _pv_path="$(xray_vmess_field "$_pv_json" path)"
    _pv_tls="$(xray_vmess_field "$_pv_json" tls)"
    _pv_sni="$(xray_vmess_field "$_pv_json" sni)"
    _pv_alpn="$(xray_vmess_field "$_pv_json" alpn)"
    _pv_fp="$(xray_vmess_field "$_pv_json" fp)"

    xray_network="$(xray_normalize_network "$_pv_net")" || return 1
    xray_header_type="$(xray_normalize_header "$_pv_header")"

    case "$_pv_tls" in
        tls)     xray_security="tls" ;;
        reality) xray_security="reality" ;;
        *)       xray_security="none" ;;
    esac

    xray_host="$_pv_host"
    xray_path="$_pv_path"
    xray_sni="$_pv_sni"
    xray_alpn="$_pv_alpn"
    xray_fp="$_pv_fp"

    if [ "$xray_network" = "grpc" ]; then
        xray_service="$_pv_path"
        xray_path=""
    fi

    return 0
}

# vless://id@host:port?params#name and trojan://password@host:port?params#name
xray_parse_url_link() {
    _pu_scheme="${1%%://*}"
    _pu_head="${1%%#*}"

    if [ "$_pu_head" = "$1" ]; then
        _pu_label=""
    else
        _pu_label="$(url_decode "${1#*#}")"
    fi

    _pu_body="${_pu_head#*://}"

    case "$_pu_body" in
        *'?'*)
            XRAY_PARSED_QUERY="${_pu_body#*\?}"
            _pu_body="${_pu_body%%\?*}"
            ;;
    esac

    case "$_pu_body" in
        *'@'*)
            _pu_id="$(url_decode "${_pu_body%@*}")"
            _pu_hostport="${_pu_body##*@}"
            ;;
        *)
            _pu_id=""
            _pu_hostport="$_pu_body"
            ;;
    esac

    xray_proto="$_pu_scheme"
    xray_id="$_pu_id"
    xray_label="$_pu_label"
    xray_parse_hostport "$_pu_hostport"

    xray_network="$(xray_normalize_network "$(xray_get_param type)")" || return 1
    xray_header_type="$(xray_normalize_header "$(xray_get_param headerType)")"
    xray_flow="$(xray_get_param flow)"
    xray_encryption="$(xray_get_param encryption)"

    xray_host="$(xray_get_param host)"
    xray_sni="$(xray_get_param sni)"

    if [ -z "$xray_sni" ]; then
        xray_sni="$(xray_get_param peer)"
    fi

    case "$xray_network" in
        ws|httpupgrade|xhttp) ;;
        *)
            if [ -z "$xray_sni" ]; then
                xray_sni="$xray_host"
            fi
            ;;
    esac

    xray_path="$(xray_get_param path)"
    xray_service="$(xray_get_param serviceName)"

    if [ -z "$xray_service" ]; then
        xray_service="$(xray_get_param servicename)"
    fi

    if [ "$xray_network" = "grpc" ]; then
        if [ -z "$xray_service" ]; then
            xray_service="$xray_path"
        fi
        xray_path=""
    fi

    xray_grpc_mode="$(xray_get_param mode)"
    xray_xhttp_mode="$(xray_get_param mode)"

    xray_fp="$(xray_get_param fp)"
    xray_alpn="$(xray_get_param alpn)"
    xray_pbk="$(xray_get_param pbk)"
    xray_sid="$(xray_get_param sid)"
    xray_spx="$(xray_get_param spx)"

    xray_security="$(xray_get_param security)"

    if [ -z "$xray_security" ]; then
        case "$(xray_get_param tls)" in
            1|true)
                xray_security="tls"
                ;;
            *)
                if [ "$_pu_scheme" = "trojan" ]; then
                    xray_security="tls"
                else
                    xray_security="none"
                fi
                ;;
        esac
    fi

    _pu_insecure="$(xray_get_param allowInsecure)"

    if [ -z "$_pu_insecure" ]; then
        _pu_insecure="$(xray_get_param insecure)"
    fi

    case "$_pu_insecure" in
        1|true) xray_insecure="1" ;;
        *)      xray_insecure="0" ;;
    esac

    return 0
}

# Normalise a share link into the xray_* globals consumed by xray_write_config.
xray_parse_link() {
    xray_proto=""
    xray_label=""
    xray_address=""
    xray_port=""
    xray_id=""
    xray_scy=""
    xray_flow=""
    xray_encryption=""
    xray_network="tcp"
    xray_security="none"
    xray_sni=""
    xray_fp=""
    xray_alpn=""
    xray_path=""
    xray_host=""
    xray_service=""
    xray_grpc_mode=""
    xray_xhttp_mode=""
    xray_pbk=""
    xray_sid=""
    xray_spx=""
    xray_header_type="none"
    xray_insecure="0"

    XRAY_PARSED_QUERY=""

    case "$1" in
        vmess://*)
            xray_parse_vmess_link "$1" || return 1
            ;;
        vless://*|trojan://*)
            xray_parse_url_link "$1" || return 1
            ;;
        *)
            printf '%s[✗] Unsupported link. Expected vless://, vmess:// or trojan://.%s\n' \
                "$RED" "$NC"
            return 1
            ;;
    esac

    case "$xray_security" in
        xtls) xray_security="tls" ;;
    esac

    if [ -z "$xray_port" ]; then
        xray_port="443"
    fi

    case "$xray_port" in
        ''|*[!0-9]*)
            printf '%s[✗] Invalid port "%s" in the share link.%s\n' \
                "$RED" "$xray_port" "$NC"
            return 1
            ;;
    esac

    if [ "$xray_port" -lt 1 ] || [ "$xray_port" -gt 65535 ]; then
        printf '%s[✗] Port must be between 1 and 65535.%s\n' "$RED" "$NC"
        return 1
    fi

    if [ -z "$xray_address" ]; then
        printf '%s[✗] Could not read the server address from the share link.%s\n' \
            "$RED" "$NC"
        return 1
    fi

    if [ -z "$xray_id" ]; then
        printf '%s[✗] Could not read the UUID or password from the share link.%s\n' \
            "$RED" "$NC"
        return 1
    fi

    if [ "$xray_security" = "reality" ] && [ -z "$xray_pbk" ]; then
        printf '%s[✗] This REALITY node is missing its "pbk" public key parameter.%s\n' \
            "$RED" "$NC"
        return 1
    fi

    if [ "$xray_security" != "none" ] && [ -z "$xray_sni" ]; then
        xray_sni="$xray_address"
    fi

    if [ -z "$xray_label" ]; then
        xray_label="${xray_proto}@${xray_address}"
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Xray Config Generation
# ------------------------------------------------------------------------------

# Build the "streamSettings" object for the proxy outbound.
xray_stream_settings() {
    _ss_out="\"network\": \"$(json_escape "$xray_network")\""

    case "$xray_network" in
        tcp)
            if [ "$xray_header_type" = "http" ]; then
                _ss_chost="$xray_host"

                if [ -z "$_ss_chost" ]; then
                    _ss_chost="$xray_sni"
                fi

                if [ -z "$_ss_chost" ]; then
                    _ss_chost="$xray_address"
                fi

                _ss_out="${_ss_out}, \"tcpSettings\": {\"header\": {\"type\": \"http\", \"request\": {\"version\": \"1.1\", \"method\": \"GET\", \"path\": [\"/\"], \"headers\": {\"Host\": [\"$(json_escape "$_ss_chost")\"]}}}}"
            else
                _ss_out="${_ss_out}, \"tcpSettings\": {\"header\": {\"type\": \"none\"}}"
            fi
            ;;
        ws)
            _ss_path="$xray_path"

            if [ -z "$_ss_path" ]; then
                _ss_path="/"
            fi

            if [ -n "$xray_host" ]; then
                _ss_out="${_ss_out}, \"wsSettings\": {\"path\": \"$(json_escape "$_ss_path")\", \"headers\": {\"Host\": \"$(json_escape "$xray_host")\"}}"
            else
                _ss_out="${_ss_out}, \"wsSettings\": {\"path\": \"$(json_escape "$_ss_path")\"}"
            fi
            ;;
        httpupgrade)
            _ss_path="$xray_path"

            if [ -z "$_ss_path" ]; then
                _ss_path="/"
            fi

            _ss_out="${_ss_out}, \"httpupgradeSettings\": {\"path\": \"$(json_escape "$_ss_path")\""

            if [ -n "$xray_host" ]; then
                _ss_out="${_ss_out}, \"host\": \"$(json_escape "$xray_host")\""
            fi

            _ss_out="${_ss_out}}"
            ;;
        xhttp)
            _ss_path="$xray_path"

            if [ -z "$_ss_path" ]; then
                _ss_path="/"
            fi

            _ss_mode="$xray_xhttp_mode"

            if [ -z "$_ss_mode" ]; then
                _ss_mode="auto"
            fi

            _ss_out="${_ss_out}, \"xhttpSettings\": {\"path\": \"$(json_escape "$_ss_path")\", \"mode\": \"$(json_escape "$_ss_mode")\""

            if [ -n "$xray_host" ]; then
                _ss_out="${_ss_out}, \"host\": \"$(json_escape "$xray_host")\""
            fi

            _ss_out="${_ss_out}}"
            ;;
        grpc)
            _ss_out="${_ss_out}, \"grpcSettings\": {\"serviceName\": \"$(json_escape "$xray_service")\""

            case "$xray_grpc_mode" in
                multi|multimode)
                    _ss_out="${_ss_out}, \"multiMode\": true"
                    ;;
                gun)
                    _ss_out="${_ss_out}, \"multiMode\": false"
                    ;;
            esac

            if [ -n "$xray_host" ]; then
                _ss_out="${_ss_out}, \"authority\": \"$(json_escape "$xray_host")\""
            fi

            _ss_out="${_ss_out}}"
            ;;
        kcp)
            _ss_out="${_ss_out}, \"kcpSettings\": {\"header\": {\"type\": \"none\"}}"
            ;;
    esac

    _ss_out="${_ss_out}, \"security\": \"$(json_escape "$xray_security")\""

    case "$xray_security" in
        tls)
            _ss_out="${_ss_out}, \"tlsSettings\": {\"serverName\": \"$(json_escape "$xray_sni")\""

            if [ -n "$xray_alpn" ]; then
                _ss_out="${_ss_out}, \"alpn\": $(xray_json_string_array "$xray_alpn")"
            fi

            if [ -n "$xray_fp" ]; then
                _ss_out="${_ss_out}, \"fingerprint\": \"$(json_escape "$xray_fp")\""
            fi

            _ss_out="${_ss_out}}"
            ;;
        reality)
            _ss_fp="$xray_fp"

            if [ -z "$_ss_fp" ]; then
                _ss_fp="chrome"
            fi

            _ss_spx="$xray_spx"

            if [ -z "$_ss_spx" ]; then
                _ss_spx="/"
            fi

            _ss_out="${_ss_out}, \"realitySettings\": {\"publicKey\": \"$(json_escape "$xray_pbk")\", \"fingerprint\": \"$(json_escape "$_ss_fp")\", \"serverName\": \"$(json_escape "$xray_sni")\", \"spiderX\": \"$(json_escape "$_ss_spx")\""

            if [ -n "$xray_sid" ]; then
                _ss_out="${_ss_out}, \"shortId\": \"$(json_escape "$xray_sid")\""
            fi

            _ss_out="${_ss_out}}"
            ;;
    esac

    printf '{%s}' "$_ss_out"
}

# Build the "settings" object of the proxy outbound.
xray_outbound_settings() {
    case "$xray_proto" in
        vless|vmess)
            _os_user="{\"id\": \"$(json_escape "$xray_id")\""

            if [ -n "$xray_encryption" ]; then
                _os_user="${_os_user}, \"encryption\": \"$(json_escape "$xray_encryption")\""
            fi

            if [ -n "$xray_flow" ]; then
                _os_user="${_os_user}, \"flow\": \"$(json_escape "$xray_flow")\""
            fi

            if [ -n "$xray_scy" ]; then
                _os_user="${_os_user}, \"security\": \"$(json_escape "$xray_scy")\""
            fi

            _os_user="${_os_user}}"

            printf '{"vnext":[{"address":"%s","port":%s,"users":[%s]}]}' \
                "$(json_escape "$xray_address")" "$xray_port" "$_os_user"
            ;;
        trojan)
            printf '{"servers":[{"address":"%s","port":%s,"password":"%s"}]}' \
                "$(json_escape "$xray_address")" "$xray_port" \
                "$(json_escape "$xray_id")"
            ;;
    esac
}

# Emit the full proxy outbound object, indented to sit inside "outbounds".
xray_proxy_outbound_json() {
    printf '    {\n'
    printf '      "tag": "proxy",\n'
    printf '      "protocol": "%s",\n' "$(json_escape "$xray_proto")"
    printf '      "settings": %s,\n' "$(xray_outbound_settings)"
    printf '      "streamSettings": %s\n' "$(xray_stream_settings)"
    printf '    }'
}

# Write the Xray client configuration consumed by the container.
xray_write_config() {
    umask 077

    cat > "$XRAY_CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "socks-in",
      "listen": "${XRAY_LISTEN}",
      "port": ${XRAY_SOCKS_PORT},
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": false
      }
    },
    {
      "tag": "http-in",
      "listen": "${XRAY_LISTEN}",
      "port": ${XRAY_HTTP_PORT},
      "protocol": "http",
      "settings": {
        "auth": "noauth"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": false
      }
    }
  ],
  "outbounds": [
$(xray_proxy_outbound_json),
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {
        "response": {
          "type": "http"
        }
      }
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "domain": ["localhost", "*.localhost", "*.local"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": [
          "127.0.0.0/8",
          "10.0.0.0/8",
          "172.16.0.0/12",
          "192.168.0.0/16",
          "169.254.0.0/16",
          "fe80::/10"
        ],
        "outboundTag": "direct"
      }
    ]
  }
}
EOF

    chmod 600 "$XRAY_CONFIG_FILE"
}

# ------------------------------------------------------------------------------
# Xray Core (Docker)
# ------------------------------------------------------------------------------

xray_core_installed() {
    container_exists "$XRAY_CONTAINER"
}

xray_core_running() {
    container_running "$XRAY_CONTAINER"
}

# (Re)create the Xray container so it always picks up the current config.json.
xray_core_create() {
    if [ ! -f "$XRAY_CONFIG_FILE" ]; then
        printf '%s[✗] No Xray client configuration found. Add a node first.%s\n' \
            "$RED" "$NC"
        return 1
    fi

    if ! docker image inspect "$XRAY_IMAGE" >/dev/null 2>&1; then
        printf '%s[*] Pulling %s...%s\n' "$BLUE" "$XRAY_IMAGE" "$NC"

        if ! docker pull "$XRAY_IMAGE"; then
            printf '%s[✗] Failed to pull the Xray image.%s\n' "$RED" "$NC"
            return 1
        fi
    fi

    if container_exists "$XRAY_CONTAINER"; then
        docker rm -f "$XRAY_CONTAINER" >/dev/null 2>&1 || true
    fi

    printf '%s[*] Starting Xray core (SOCKS %s, HTTP %s)...%s\n' \
        "$BLUE" "$XRAY_SOCKS_PORT" "$XRAY_HTTP_PORT" "$NC"

    if ! docker run -d \
        --name "$XRAY_CONTAINER" \
        --restart unless-stopped \
        --network host \
        -v "${XRAY_CONFIG_FILE}:/etc/xray/config.json:ro" \
        "$XRAY_IMAGE" >/dev/null; then

        printf '%s[✗] Failed to start the Xray container.%s\n' "$RED" "$NC"
        return 1
    fi

    sleep 2

    if ! xray_core_running; then
        printf '%s[✗] Xray stopped right after startup.%s\n\n' "$RED" "$NC"
        printf '%sXray logs:%s\n' "$YELLOW" "$NC"
        docker logs --tail 30 "$XRAY_CONTAINER" 2>&1 || true
        return 1
    fi

    return 0
}

xray_core_start() {
    xray_core_create
}

xray_core_restart() {
    if ! xray_core_installed; then
        printf '%s[✗] Xray is not installed yet. Add a node first.%s\n' \
            "$RED" "$NC"
        return 1
    fi

    printf '%s[*] Restarting Xray core...%s\n' "$BLUE" "$NC"

    if ! docker restart "$XRAY_CONTAINER" >/dev/null 2>&1; then
        printf '%s[✗] Failed to restart the Xray container.%s\n' "$RED" "$NC"
        return 1
    fi

    sleep 2
    return 0
}

xray_core_stop() {
    if ! xray_core_installed; then
        printf '%s[!] Xray is not installed.%s\n' "$YELLOW" "$NC"
        return 1
    fi

    printf '%s[*] Stopping Xray core...%s\n' "$BLUE" "$NC"

    if ! docker stop "$XRAY_CONTAINER" >/dev/null 2>&1; then
        printf '%s[✗] Failed to stop the Xray container.%s\n' "$RED" "$NC"
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Xray System Proxy
# ------------------------------------------------------------------------------

xray_proxy_enabled() {
    [ -f "$XRAY_PROFILE_FILE" ]
}

# Apply the variables to this script process and to every future shell.
xray_apply_session_proxy() {
    if [ "$1" = "on" ]; then
        http_proxy="$XRAY_PROXY_URL"
        https_proxy="$XRAY_PROXY_URL"
        all_proxy="$XRAY_SOCKS_URL"
        no_proxy="$XRAY_NO_PROXY_LIST"

        HTTP_PROXY="$http_proxy"
        HTTPS_PROXY="$https_proxy"
        ALL_PROXY="$all_proxy"
        NO_PROXY="$no_proxy"

        export http_proxy https_proxy all_proxy no_proxy
        export HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
        return 0
    fi

    unset http_proxy https_proxy all_proxy no_proxy
    unset HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
    return 0
}

xray_write_profile_file() {
    _wp_tmp="${XRAY_PROFILE_FILE}.hermes.$$"

    cat > "$_wp_tmp" <<EOF
# Managed by hermes-manager (Xray). Do not edit by hand.
export http_proxy="${XRAY_PROXY_URL}"
export https_proxy="${XRAY_PROXY_URL}"
export all_proxy="${XRAY_SOCKS_URL}"
export no_proxy="${XRAY_NO_PROXY_LIST}"
export HTTP_PROXY="\${http_proxy}"
export HTTPS_PROXY="\${https_proxy}"
export ALL_PROXY="\${all_proxy}"
export NO_PROXY="\${no_proxy}"
EOF

    if ! mv "$_wp_tmp" "$XRAY_PROFILE_FILE" 2>/dev/null; then
        rm -f "$_wp_tmp"
        return 1
    fi

    chmod 644 "$XRAY_PROFILE_FILE" 2>/dev/null || true
    return 0
}

# Rewrite /etc/environment so stale proxy entries never survive a toggle.
xray_sync_environment_file() {
    _se_tmp="${XRAY_ENVIRONMENT_FILE}.hermes.$$"

    if [ -e "$XRAY_ENVIRONMENT_FILE" ]; then
        if [ ! -w "$XRAY_ENVIRONMENT_FILE" ]; then
            return 1
        fi
    elif [ ! -w "/etc" ]; then
        return 1
    fi

    if [ -f "$XRAY_ENVIRONMENT_FILE" ]; then
        grep -v -E \
'^[[:space:]]*(http_proxy|https_proxy|all_proxy|no_proxy|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY)[[:space:]]*=' \
            "$XRAY_ENVIRONMENT_FILE" > "$_se_tmp" 2>/dev/null || true
    else
        : > "$_se_tmp"
    fi

    if [ "$1" = "on" ]; then
        cat >> "$_se_tmp" <<EOF
http_proxy=${XRAY_PROXY_URL}
https_proxy=${XRAY_PROXY_URL}
all_proxy=${XRAY_SOCKS_URL}
no_proxy=${XRAY_NO_PROXY_LIST}
EOF
    fi

    if ! cat "$_se_tmp" > "$XRAY_ENVIRONMENT_FILE" 2>/dev/null; then
        rm -f "$_se_tmp"
        return 1
    fi

    rm -f "$_se_tmp"
    return 0
}

xray_set_system_proxy() {
    printf '%s[*] Enabling the system proxy...%s\n' "$BLUE" "$NC"

    if xray_write_profile_file; then
        _xp_profile_ok=1
    else
        _xp_profile_ok=0
    fi

    if xray_sync_environment_file on; then
        _xp_env_ok=1
    else
        _xp_env_ok=0
    fi

    xray_apply_session_proxy on

    if [ "$_xp_profile_ok" -eq 0 ] && [ "$_xp_env_ok" -eq 0 ]; then
        printf '%s[!] Could not update %s or %s (root required).%s\n' \
            "$YELLOW" "$XRAY_PROFILE_FILE" "$XRAY_ENVIRONMENT_FILE" "$NC"
        printf '    The proxy is active for this script session only.\n\n'
    fi

    if [ "$_xp_env_ok" -eq 0 ]; then
        printf '%s[!] %s is not writable, only %s was updated.%s\n' \
            "$YELLOW" "$XRAY_ENVIRONMENT_FILE" "$XRAY_PROFILE_FILE" "$NC"
    fi

    printf '\n  http_proxy  = %s\n' "$XRAY_PROXY_URL"
    printf '  https_proxy = %s\n' "$XRAY_PROXY_URL"
    printf '  all_proxy   = %s\n' "$XRAY_SOCKS_URL"
    printf '  no_proxy    = %s\n' "$XRAY_NO_PROXY_LIST"

    printf '\n  %sApplied to this script and to every new shell.%s\n' "$CYAN" "$NC"
    printf '  %sApply it to the current terminal too with:%s\n' "$CYAN" "$NC"
    printf '    . %s\n\n' "$XRAY_PROFILE_FILE"

    if enable_docker_proxy; then
        printf '  %sDocker proxy set to %s (new containers are proxied).%s\n\n' \
            "$CYAN" "$(docker_proxy_url)" "$NC"
    fi

    return 0
}

xray_unset_system_proxy() {
    printf '%s[*] Disabling the system proxy...%s\n' "$BLUE" "$NC"

    if ! rm -f "$XRAY_PROFILE_FILE" 2>/dev/null; then
        printf '%s[!] Could not remove %s (root required).%s\n' \
            "$YELLOW" "$XRAY_PROFILE_FILE" "$NC"
    fi

    xray_sync_environment_file off >/dev/null 2>&1 || true
    xray_apply_session_proxy off
    disable_docker_proxy

    printf '%s[✓] System proxy disabled.%s\n' "$GREEN" "$NC"
    printf '  %sOpen a new terminal, or run "unset http_proxy https_proxy all_proxy"\n' "$CYAN"
    printf '  to drop the variables from a shell started while it was on.%s\n\n' \
        "$NC"
    return 0
}

# ------------------------------------------------------------------------------
# Xray Latency Test
# ------------------------------------------------------------------------------

# Turn a curl "0.123" duration into whole milliseconds.
xray_seconds_to_ms() {
    case "$1" in
        ''|*[!0-9.]*)
            printf '0'
            return 0
            ;;
    esac

    _st_int="${1%%.*}"

    if [ "$_st_int" = "$1" ]; then
        _st_int="${1%.}"
    fi

    _st_frac="${1#*.}"

    if [ "$_st_frac" = "$1" ]; then
        _st_frac="0"
    fi

    while [ "${#_st_frac}" -lt 6 ]; do
        _st_frac="${_st_frac}0"
    done

    _st_frac="${_st_frac%"${_st_frac#???}"}"

    # A leading zero would make the shell read the value as octal.
    _st_frac="${_st_frac#"${_st_frac%%[!0]*}"}"

    if [ -z "$_st_frac" ]; then
        _st_frac=0
    fi

    printf '%s' "$(( _st_int * 1000 + _st_frac ))"
}

# Milliseconds since boot, from /proc/uptime (10 ms resolution).
xray_now_ms() {
    if [ -r /proc/uptime ]; then
        xray_seconds_to_ms "$(cut -d' ' -f1 /proc/uptime)"
    else
        printf '%s' "$(( $(date +%s) * 1000 ))"
    fi
}

# Fetch a URL body through the local proxy, using curl or wget.
xray_fetch_via_proxy() {
    _fv_url="$1"

    if command -v curl >/dev/null 2>&1; then
        curl -s --proxy "$XRAY_PROXY_URL" \
            --connect-timeout 10 --max-time 20 "$_fv_url" 2>/dev/null || true
        return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        http_proxy="$XRAY_PROXY_URL" https_proxy="$XRAY_PROXY_URL" \
            wget -q -O - -T 20 "$_fv_url" 2>/dev/null || true
    fi
}

# xray_probe <url> <proxy|direct> -> "<http_code> <ms>" on success.
# Returns 1 when the request failed, 2 when neither curl nor wget exists.
xray_probe() {
    _pr_url="$1"
    _pr_mode="$2"

    if command -v curl >/dev/null 2>&1; then
        if [ "$_pr_mode" = "proxy" ]; then
            _pr_raw="$(curl -s -o /dev/null --proxy "$XRAY_PROXY_URL" \
                --connect-timeout 10 --max-time 25 \
                -w '%{http_code} %{time_total}' "$_pr_url" 2>/dev/null)"
        else
            _pr_raw="$(curl -s -o /dev/null --noproxy '*' \
                --connect-timeout 10 --max-time 25 \
                -w '%{http_code} %{time_total}' "$_pr_url" 2>/dev/null)"
        fi

        if [ $? -ne 0 ]; then
            return 1
        fi

        _pr_code="${_pr_raw%% *}"
        _pr_total="${_pr_raw#* }"
        _pr_total="${_pr_total%% *}"

        printf '%s %s' "$_pr_code" "$(xray_seconds_to_ms "$_pr_total")"
        return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        _pr_hdr="/tmp/hermes-xray-probe.$$"
        _pr_body="/tmp/hermes-xray-body.$$"
        _pr_t0="$(xray_now_ms)"

        if [ "$_pr_mode" = "proxy" ]; then
            http_proxy="$XRAY_PROXY_URL" https_proxy="$XRAY_PROXY_URL" \
                wget -S -O "$_pr_body" -T 25 "$_pr_url" 2>"$_pr_hdr"
        else
            env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
                -u all_proxy -u ALL_PROXY \
                wget -S -O "$_pr_body" -T 25 "$_pr_url" 2>"$_pr_hdr"
        fi

        _pr_rc=$?
        _pr_t1="$(xray_now_ms)"
        rm -f "$_pr_body"

        _pr_code="$(sed -n \
            's/^[[:space:]]*HTTP\/[0-9.]*[[:space:]]\{1,\}\([0-9][0-9][0-9]\).*/\1/p' \
            "$_pr_hdr" | tail -n 1)"
        rm -f "$_pr_hdr"

        if [ "$_pr_rc" -ne 0 ]; then
            return 1
        fi

        printf '%s %s' "${_pr_code:-000}" "$(( _pr_t1 - _pr_t0 ))"
        return 0
    fi

    return 2
}

# Probe a URL through the local HTTP inbound and compare with a direct call.
xray_test_latency() {
    if ! xray_core_running; then
        fail "The Xray core is not running. Start it first."
        return 1
    fi

    printf '\n%s[*] Testing %s through %s...%s\n\n' \
        "$BOLD" "$XRAY_TEST_URL" "$XRAY_PROXY_URL" "$NC"

    _xt_result="$(xray_probe "$XRAY_TEST_URL" proxy)"
    _xt_status=$?

    if [ "$_xt_status" -eq 2 ]; then
        fail "Neither curl nor wget is available in this sandbox."
        return 1
    fi

    if [ "$_xt_status" -ne 0 ]; then
        fail "Proxy request failed."
        printf '  The core is up, but the node is down, blocked or misconfigured.\n'
        return 1
    fi

    _xt_code="${_xt_result%% *}"
    _xt_ms="${_xt_result#* }"

    _xt_ip="$(xray_fetch_via_proxy "$XRAY_TEST_IP_URL" | tr -d '\r\n')"

    _xt_direct_result="$(xray_probe "$XRAY_TEST_URL" direct)"
    _xt_direct_ms=""
    _xt_delta=""

    if [ -n "$_xt_direct_result" ]; then
        _xt_direct_ms="${_xt_direct_result#* }"
        _xt_delta="$(( _xt_ms - _xt_direct_ms ))"

        if [ "$_xt_delta" -lt 0 ]; then
            _xt_delta="$(( -_xt_delta ))"
        fi
    fi

    printf '%s  Proxy latency:   %s%s ms%s\n' \
        "$BOLD" "$CYAN" "$_xt_ms" "$NC"

    printf '  HTTP status:     %s%s%s\n' "$CYAN" "$_xt_code" "$NC"

    if [ -n "$_xt_ip" ]; then
        printf '  Egress IP:       %s%s%s\n' "$CYAN" "$_xt_ip" "$NC"
    fi

    if [ -n "$_xt_direct_ms" ]; then
        printf '  Direct latency:  %s%s ms%s\n' "$CYAN" "$_xt_direct_ms" "$NC"
        printf '  Difference:      %s+-%s ms\n' "$CYAN" "$_xt_delta" "$NC"
    else
        printf '  Direct latency:  %sunreachable (the node is required)%s\n' \
            "$YELLOW" "$NC"
    fi

    if [ -n "$XRAY_NODE_LABEL" ]; then
        printf '  Node:            %s%s%s\n\n' "$CYAN" "$XRAY_NODE_LABEL" "$NC"
    else
        printf '\n'
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Xray Node Management
# ------------------------------------------------------------------------------

xray_show_config() {
    if [ ! -f "$XRAY_CONFIG_FILE" ]; then
        printf '%s[!] No Xray configuration found yet.%s\n' "$YELLOW" "$NC"
        return 1
    fi

    printf '%s--- Xray client config (%s) ---%s\n\n' \
        "$BOLD" "$XRAY_CONFIG_FILE" "$NC"

    cat "$XRAY_CONFIG_FILE"
    printf '\n'
    return 0
}

xray_add_node() {
    clear_screen
    printf '%s--- Add / Change Node ---%s\n\n' "$BOLD" "$NC"

    load_config

    if [ -f "$XRAY_LINK_FILE" ]; then
        printf 'Current node:  %s%s%s\n' \
            "$CYAN" "${XRAY_NODE_LABEL:-Unknown}" "$NC"
    else
        printf 'Current node:  %snone%s\n' "$YELLOW" "$NC"
    fi

    printf '\nPaste a vless://, vmess:// or trojan:// share link:\n'
    printf '> '
    read -r xray_new_link

    if [ -z "$xray_new_link" ]; then
        printf '\n%s[!] No link entered.%s\n' "$YELLOW" "$NC"
        return 1
    fi

    if ! xray_parse_link "$xray_new_link"; then
        return 1
    fi

    printf '\n%sParsed node%s\n\n' "$BOLD" "$NC"
    printf '  Name:       %s%s%s\n' "$CYAN" "$xray_label" "$NC"
    printf '  Protocol:   %s%s%s\n' "$CYAN" "$xray_proto" "$NC"
    printf '  Address:    %s%s:%s%s\n' \
        "$CYAN" "$xray_address" "$xray_port" "$NC"
    printf '  Credential: %s%s%s\n' \
        "$CYAN" "$(redact_secret "$xray_id")" "$NC"
    printf '  Transport:  %s%s%s\n' "$CYAN" "$xray_network" "$NC"
    printf '  Security:   %s%s%s\n' "$CYAN" "$xray_security" "$NC"

    if [ "$xray_security" != "none" ]; then
        printf '  SNI:        %s%s%s\n' "$CYAN" "$xray_sni" "$NC"
    fi

    if [ "$xray_insecure" = "1" ]; then
        printf '\n  %sThis link requests allowInsecure, which recent Xray cores reject.%s\n' \
            "$YELLOW" "$NC"
    fi

    printf '\nApply this node and start the core? [Y/n]: '
    read -r xray_confirm

    case "$xray_confirm" in
        ''|[Yy]*) ;;
        *)
            printf '%s[!] Cancelled.%s\n' "$YELLOW" "$NC"
            return 1
            ;;
    esac

    if ! xray_write_config; then
        printf '\n%s[✗] Could not write %s.%s\n' \
            "$RED" "$XRAY_CONFIG_FILE" "$NC"
        return 1
    fi

    printf '%s\n' "$xray_new_link" > "$XRAY_LINK_FILE"
    chmod 600 "$XRAY_LINK_FILE"

    XRAY_NODE_LABEL="$xray_label"
    save_config

    if ! ensure_docker; then
        return 1
    fi

    if ! xray_core_create; then
        return 1
    fi

    printf '\n%s[✓] Xray core is running with "%s".%s\n' \
        "$GREEN" "$xray_label" "$NC"
    printf '  SOCKS: %s\n' "$XRAY_SOCKS_URL"
    printf '  HTTP:  %s\n\n' "$XRAY_PROXY_URL"

    if ! xray_proxy_enabled; then
        xray_set_system_proxy
    fi

    return 0
}

xray_toggle_proxy() {
    if xray_proxy_enabled; then
        xray_unset_system_proxy
        return 0
    fi

    if ! xray_core_running; then
        warn "The Xray core is not running; traffic stays blocked until it starts."
    fi

    xray_set_system_proxy
    return 0
}

update_xray() {
    clear_screen
    screen_title "Xray · Update"

    if ! ensure_docker; then
        return
    fi

    info "Pulling the latest Xray image..."

    if ! docker pull "$XRAY_IMAGE"; then
        fail "Failed to pull the Xray image."
        return
    fi

    if xray_core_installed; then
        if xray_core_create; then
            ok "Xray core updated and running."
        fi
    else
        ok "Xray image updated."
    fi
}

uninstall_xray() {
    clear_screen
    screen_title "Xray · Uninstall"

    if ! ensure_docker; then
        return
    fi

    if xray_proxy_enabled; then
        xray_unset_system_proxy >/dev/null 2>&1 || true
    fi

    if container_exists "$XRAY_CONTAINER"; then
        if confirm_yes "Remove the Xray container?"; then
            docker rm -f "$XRAY_CONTAINER" >/dev/null 2>&1 || true
            ok "Xray container removed."
        else
            warn "Cancelled."
            return
        fi
    else
        warn "Xray is not installed."
    fi

    if [ -d "$XRAY_DATA_DIR" ]; then
        if confirm_no "Delete the Xray config and node link (${XRAY_DATA_DIR})?"; then
            rm -rf "$XRAY_DATA_DIR"
            XRAY_NODE_LABEL=""
            save_config
            ok "Xray config deleted."
        else
            info "Config kept at ${XRAY_DATA_DIR}."
        fi
    fi

    if confirm_no "Remove the Xray image?"; then
        docker rmi "$XRAY_IMAGE" >/dev/null 2>&1 || true
        ok "Image removed."
    fi
}

# ------------------------------------------------------------------------------
# Xray Menu
# ------------------------------------------------------------------------------

xray_menu() {
    while true; do
        clear_screen
        load_config

        screen_title "Xray Proxy"

        _xr_state="$(container_state "$XRAY_CONTAINER")"

        if xray_proxy_enabled; then _xr_proxy="enabled"; else _xr_proxy="disabled"; fi
        if docker_proxy_enabled; then _xr_dproxy="enabled"; else _xr_dproxy="disabled"; fi

        box_top
        box_kv "  Core          " "$_xr_state" "$(state_color "$_xr_state")"

        if [ "$_xr_proxy" = "enabled" ]; then
            box_kv "  System proxy  " "$_xr_proxy" "$GREEN"
        else
            box_kv "  System proxy  " "$_xr_proxy" "$YELLOW"
        fi

        if [ "$_xr_dproxy" = "enabled" ]; then
            box_kv "  Docker proxy  " "$_xr_dproxy" "$GREEN"
        else
            box_kv "  Docker proxy  " "$_xr_dproxy" "$YELLOW"
        fi

        box_text "$DIM" "  Node          ${XRAY_NODE_LABEL:-none}"

        if [ -f "$XRAY_CONFIG_FILE" ]; then
            box_text "$DIM" "  SOCKS / HTTP  ${XRAY_SOCKS_URL} / ${XRAY_PROXY_URL}"
        fi

        box_bottom

        printf '\n'
        menu_item 1 "Add / change node link"
        menu_item 2 "Pause / resume system proxy" "host shells + new containers"
        menu_item 3 "Toggle Docker proxy" "proxy for newly created containers"
        menu_item 4 "Restart core"
        menu_item 5 "Stop core"
        menu_item 6 "Start core"
        menu_item 7 "Update core image"
        menu_item 8 "Test proxy latency"
        menu_item 9 "Show logs"
        menu_item 10 "Show client config"
        menu_item 11 "Uninstall"

        printf '\n'
        menu_item 0 "Back"

        printf '\n  Select [0-11]: '
        read -r _xr_choice

        case "$_xr_choice" in
            1) xray_add_node ;;
            2) xray_toggle_proxy ;;
            3)
                if docker_proxy_enabled; then
                    disable_docker_proxy
                    ok "Docker proxy disabled."
                elif enable_docker_proxy; then
                    ok "Docker proxy enabled for new containers."
                fi
                ;;
            4)
                if ensure_docker && xray_core_restart; then
                    ok "Xray core restarted."
                fi
                ;;
            5)
                if ensure_docker; then
                    xray_core_stop
                fi
                ;;
            6)
                if ensure_docker && xray_core_start; then
                    ok "Xray core is running."
                fi
                ;;
            7) update_xray ;;
            8) xray_test_latency ;;
            9) show_logs_for "$XRAY_CONTAINER" ;;
            10) xray_show_config ;;
            11) uninstall_xray ;;
            0) return ;;
            *) fail "Invalid option." ;;
        esac

        pause_menu
    done
}

# ------------------------------------------------------------------------------
# Manager Settings
# ------------------------------------------------------------------------------

show_manager_config() {
    clear_screen
    screen_title "Manager Configuration"

    load_config

    _cmd_path="$(cli_command_path)"

    printf '\n'
    printf '  %-22s %s\n' "Config file" "$CONFIG_FILE"
    printf '  %-22s %s\n' "CLI command" "${_cmd_path:-not on PATH}"
    printf '  %-22s %s\n' "Hermes API URL" "${HERMES_API_URL:-not set}"
    printf '  %-22s %s\n' "Hermes API token" "$(redact_secret "${HERMES_API_TOKEN:-}")"
    printf '  %-22s %s\n' "Telegram token" "$(redact_secret "${TELEGRAM_BOT_TOKEN:-}")"
    printf '  %-22s %s\n' "Telegram users" "${TELEGRAM_ALLOWED_USERS:-not set}"
    printf '  %-22s %s\n' "Hermes model" "$HERMES_MODEL"
    printf '  %-22s %s\n' "9Router port" "$NINEROUTER_PORT"
    printf '  %-22s %s\n' "FreeLLMAPI port" "$FREELLMAPI_PORT"
    printf '  %-22s %s\n' "Xray node" "${XRAY_NODE_LABEL:-not set}"
    printf '\n'
}

reset_all_data() {
    clear_screen
    screen_title "Reset All Data"

    warn "This removes every container, image and data directory managed here."

    printf '\n  %s\n' "$HERMES_DATA_DIR"
    printf '  %s\n' "$NINEROUTER_DATA_DIR"
    printf '  %s\n' "$FREELLMAPI_DATA_DIR"
    printf '  %s\n' "$XRAY_DATA_DIR"

    if ! confirm_no "Really continue?"; then
        warn "Cancelled."
        return
    fi

    if ! confirm_no "This cannot be undone. Delete everything?"; then
        warn "Cancelled."
        return
    fi

    if docker_ready; then
        if xray_proxy_enabled; then
            xray_unset_system_proxy >/dev/null 2>&1 || true
        fi

        for _ra_container in \
            "$HERMES_CONTAINER" "$NINEROUTER_CONTAINER" \
            "$FREELLMAPI_CONTAINER" "$XRAY_CONTAINER"; do

            docker rm -f "$_ra_container" >/dev/null 2>&1 || true
        done

        for _ra_image in \
            "hermes-agent:latest" "$NINEROUTER_IMAGE" \
            "$FREELLMAPI_IMAGE" "$XRAY_IMAGE"; do

            docker rmi "$_ra_image" >/dev/null 2>&1 || true
        done
    fi

    disable_docker_proxy
    rm -f "$CONFIG_FILE"
    rm -rf "$HERMES_DATA_DIR" "$NINEROUTER_DATA_DIR" \
        "$FREELLMAPI_DATA_DIR" "$XRAY_DATA_DIR" "$HERMES_REPO_DIR"

    ok "All managed data removed."
}

manager_menu() {
    while true; do
        clear_screen
        load_config

        screen_title "Manager Settings"

        if docker_proxy_enabled; then _mg_dproxy="enabled"; else _mg_dproxy="disabled"; fi

        printf '\n'
        menu_item 1 "Update manager" "re-download install.sh"
        menu_item 2 "Reinstall CLI command" "write ${CLI_COMMAND} to PATH"
        menu_item 3 "Docker proxy (${_mg_dproxy})" "proxy for new containers"
        menu_item 4 "Show manager config"
        menu_item 5 "Reset all data" "destructive"

        printf '\n'
        menu_item 0 "Back"

        printf '\n  Select [0-5]: '
        read -r _mg_choice

        case "$_mg_choice" in
            1) update_manager ;;
            2)
                if install_cli_command; then
                    ok "Installed: $(cli_command_path)"
                else
                    fail "Could not install ${CLI_COMMAND} (need a writable dir on PATH)."
                fi
                ;;
            3)
                if docker_proxy_enabled; then
                    disable_docker_proxy
                    ok "Docker proxy disabled."
                elif enable_docker_proxy; then
                    ok "Docker proxy enabled. Recreate containers to apply it."
                fi
                ;;
            4) show_manager_config ;;
            5) reset_all_data ;;
            0) return ;;
            *) fail "Invalid option." ;;
        esac

        pause_menu
    done
}

# ------------------------------------------------------------------------------
# Main Menu
# ------------------------------------------------------------------------------

install_cli_command >/dev/null 2>&1 || true

while true; do
    clear_screen
    render_dashboard

    section "Setup"
    menu_item 1 "Hermes" "install · rebuild · update"
    menu_item 2 "9Router" "install · update · reconfigure"
    menu_item 3 "FreeLLMAPI" "install · update · reconfigure"
    menu_item 4 "Xray proxy" "node · system proxy · core"

    section "Manage"
    menu_item 5 "Hermes API endpoint & token"
    menu_item 6 "Telegram bot & allowed users"
    menu_item 7 "Hermes configuration"
    menu_item 8 "Container logs"
    menu_item 9 "Shell into a container"
    menu_item 10 "Manager settings"

    printf '\n'
    menu_item 0 "Exit"

    printf '\n  Select [0-10]: '
    read -r choice

    case "$choice" in
        1) hermes_menu ;;
        2) ninrouter_menu ;;
        3) freellmapi_menu ;;
        4) xray_menu ;;
        5) set_hermes_api ;;
        6) set_telegram ;;
        7) show_hermes_config ;;
        8) show_logs ;;
        9) exec_in_container ;;
        10) manager_menu ;;
        0) printf '\n  %sBye.%s\n' "$GREEN" "$NC"; exit 0 ;;
        *) fail "Invalid option." ;;
    esac

    case "$choice" in
        1|2|3|4|10|0) ;;
        *) pause_menu ;;
    esac
done