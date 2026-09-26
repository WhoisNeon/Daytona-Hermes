#!/bin/sh

set -u

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------

SCRIPT_VERSION="v0.2.0"

BASE_DIR="${HOME}/hermes-manager"
CONFIG_FILE="${BASE_DIR}/config.env"

HERMES_DATA_DIR="/data/hermes"
NINEROUTER_DATA_DIR="${BASE_DIR}/9router-data"

HERMES_REPO_URL="https://github.com/lovexbytes/hermes-railway-template/archive/refs/heads/main.tar.gz"
HERMES_REPO_DIR="${BASE_DIR}/hermes-railway-template"

HERMES_CONTAINER="hermes"
NINEROUTER_CONTAINER="9router"
FREELLMAPI_CONTAINER="freellmapi"

NINEROUTER_IMAGE="ghcr.io/whoisneon/9router:latest"
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

XRAY_LISTEN="127.0.0.1"
XRAY_SOCKS_PORT="10808"
XRAY_HTTP_PORT="10809"

XRAY_PROXY_URL="http://${XRAY_LISTEN}:${XRAY_HTTP_PORT}"
XRAY_SOCKS_URL="socks5://${XRAY_LISTEN}:${XRAY_SOCKS_PORT}"
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
NC="$(printf '\033[0m')"

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
# Banner
# ------------------------------------------------------------------------------

render_banner() {
    version="$(get_version)"
    author_url="https://github.com/WhoisNeon/Daytona-Hermes"

    link_start="\033]8;;${author_url}\033\\"
    link_end="\033]8;;\033\\"

    printf '%s%s\n' "$CYAN" "$BOLD"
    printf '  _   _                                    _                    _   \n'
    printf ' | | | | ___ _ __ _ __ ___   ___  ___     / \\   __ _  ___ _ __ | |_ \n'
    printf ' | |_| |/ _ \\ '\''__| '\''_ ` _ \\ / _ \\/ __|   / _ \\ / _` |/ _ \\ '\''_ \\| __|\n'
    printf ' |  _  |  __/ |  | | | | | |  __/\\__ \\  / ___ \\ (_| |  __/ | | | |_ \n'
    printf ' |_| |_|\\___|_|  |_| |_| |_|\\___||___/ /_/   \\_\\__, |\\___|_| |_|\\__|\n'
    printf '                                               |___/                \n'
    printf '\n'
    printf '       Daytona Sandbox Edition • By %bWhoisNeon%b • %s\n' \
        "$link_start" "$link_end" "$version"
    printf '%s\n' "$NC"
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
# Status
# ------------------------------------------------------------------------------

render_status() {
    load_config

    if container_running "$HERMES_CONTAINER"; then
        hermes_status="${GREEN}Running${NC}"
    elif container_exists "$HERMES_CONTAINER"; then
        hermes_status="${YELLOW}Stopped${NC}"
    else
        hermes_status="${RED}Not installed${NC}"
    fi

    is_router_installed=0
    if container_running "$NINEROUTER_CONTAINER"; then
        router_status="${GREEN}Running${NC}"
        is_router_installed=1
    elif container_exists "$NINEROUTER_CONTAINER"; then
        router_status="${YELLOW}Stopped${NC}"
        is_router_installed=1
    else
        router_status="${RED}Not installed${NC}"
    fi

    daytona_id="$(get_daytona_id)"

    printf '%s───────────────────────────────────────────────────────────────────────────%s\n' \
      "$CYAN" "$NC"

    printf '%s%sStatus%s\n\n' "$BOLD" "$CYAN" "$NC"

    printf '  Hermes:                    %s\n' "$hermes_status"

    printf '  Hermes API endpoint:       %s%s%s\n' \
        "$CYAN" "${HERMES_API_URL:-Not set}" "$NC"

    printf '  Hermes API token:          %s%s%s\n' \
        "$CYAN" "$(redact_secret "${HERMES_API_TOKEN:-}")" "$NC"

    printf '\n'

    printf '  Telegram bot token:        %s%s%s\n' \
        "$CYAN" "$(redact_secret "${TELEGRAM_BOT_TOKEN:-}")" "$NC"

    printf '  Telegram allowed users:    %s%s%s\n' \
        "$CYAN" "${TELEGRAM_ALLOWED_USERS:-Not set}" "$NC"

    printf '\n'

    printf '  9Router:                   %s\n' "$router_status"

    if [ "$is_router_installed" -eq 1 ]; then
        printf '  9Router port:              %s%s%s\n' \
            "$CYAN" "$NINEROUTER_PORT" "$NC"

        router_ip="$(get_container_ip "$NINEROUTER_CONTAINER")"
        router_host="${router_ip:-localhost}"

        printf '  9Router local URL:         %shttp://%s:%s%s\n' \
            "$CYAN" "$router_host" "$NINEROUTER_PORT" "$NC"

        printf '  9Router public URL:        %shttps://%s-%s.proxy.daytona.work%s\n' \
            "$CYAN" "$NINEROUTER_PORT" "$daytona_id" "$NC"
    fi

    printf '\n'

    is_freellmapi_installed=0
    if container_running "$FREELLMAPI_CONTAINER"; then
        freellmapi_status="${GREEN}Running${NC}"
        is_freellmapi_installed=1
    elif container_exists "$FREELLMAPI_CONTAINER"; then
        freellmapi_status="${YELLOW}Stopped${NC}"
        is_freellmapi_installed=1
    else
        freellmapi_status="${RED}Not installed${NC}"
    fi

    printf '  FreeLLMAPI:                %s\n' "$freellmapi_status"

    if [ "$is_freellmapi_installed" -eq 1 ]; then
        printf '  FreeLLMAPI port:           %s%s%s\n' \
            "$CYAN" "$FREELLMAPI_PORT" "$NC"

        freellmapi_ip="$(get_container_ip "$FREELLMAPI_CONTAINER")"
        freellmapi_host="${freellmapi_ip:-localhost}"

        printf '  FreeLLMAPI local URL:      %shttp://%s:%s%s\n' \
            "$CYAN" "$freellmapi_host" "$FREELLMAPI_PORT" "$NC"

        printf '  FreeLLMAPI public URL:     %shttps://%s-%s.proxy.daytona.work%s\n' \
            "$CYAN" "$FREELLMAPI_PORT" "$daytona_id" "$NC"
    fi

    printf '\n'

    if container_running "$XRAY_CONTAINER"; then
        xray_status="${GREEN}Running${NC}"
    elif container_exists "$XRAY_CONTAINER"; then
        xray_status="${YELLOW}Stopped${NC}"
    else
        xray_status="${RED}Not installed${NC}"
    fi

    if xray_proxy_enabled; then
        xray_proxy_status="${GREEN}Enabled${NC}"
    else
        xray_proxy_status="${YELLOW}Disabled${NC}"
    fi

    printf '  Xray core:                 %s\n' "$xray_status"
    printf '  Xray system proxy:         %s\n' "$xray_proxy_status"

    if [ -n "$XRAY_NODE_LABEL" ]; then
        printf '  Xray node:                 %s%s%s\n' \
            "$CYAN" "$XRAY_NODE_LABEL" "$NC"
    fi

    if [ -f "$XRAY_CONFIG_FILE" ]; then
        printf '  Xray SOCKS / HTTP:         %s%s / %s%s\n' \
            "$CYAN" "$XRAY_SOCKS_URL" "$XRAY_PROXY_URL" "$NC"
    fi

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
# Install Hermes
# ------------------------------------------------------------------------------

install_hermes() {
    clear_screen
    printf '%s--- Install Hermes ---%s\n\n' "$BOLD" "$NC"

    if ! ensure_docker; then
        return
    fi

    if container_exists "$HERMES_CONTAINER"; then
        printf '%s[!] Hermes already exists.%s\n\n' "$YELLOW" "$NC"

        printf '1. Restart\n'
        printf '2. Rebuild\n'
        printf '0. Cancel\n\n'

        printf 'Select [0-2]: '
        read -r option

        case "$option" in
            1)
                docker restart "$HERMES_CONTAINER" >/dev/null
                printf '%s[✓] Hermes restarted.%s\n' "$GREEN" "$NC"
                return
                ;;
            2)
                docker rm -f "$HERMES_CONTAINER" >/dev/null 2>&1 || true
                ;;
            0|*)
                return
                ;;
        esac
    fi

    if ! prepare_hermes_source; then
        return
    fi

    write_hermes_env

    cd "$HERMES_REPO_DIR" || return

    if [ ! -f Dockerfile ]; then
        printf '%s[✗] Hermes template does not contain a Dockerfile.%s\n' \
            "$RED" "$NC"
        return
    fi

    printf '%s[*] Building Hermes image...%s\n' "$BLUE" "$NC"

    if ! docker build \
        --build-arg HERMES_IMAGE_VERSION=latest \
        -t hermes-agent:latest .; then

        printf '%s[✗] Hermes Docker build failed.%s\n' "$RED" "$NC"
        return
    fi

    printf '%s[*] Starting Hermes...%s\n' "$BLUE" "$NC"

    if ! docker run -d \
        --name "$HERMES_CONTAINER" \
        --restart unless-stopped \
        --env-file "${HERMES_REPO_DIR}/.env" \
        -v "${HERMES_DATA_DIR}:/data" \
        hermes-agent:latest; then

        printf '%s[✗] Failed to start Hermes.%s\n' "$RED" "$NC"
        return
    fi

    sleep 4

    if container_running "$HERMES_CONTAINER"; then
        printf '%s[✓] Hermes installed and running.%s\n' \
            "$GREEN" "$NC"

        configure_hermes_inside_container
    else
        printf '%s[✗] Hermes stopped after startup.%s\n' \
            "$RED" "$NC"

        printf '\n%sHermes logs:%s\n' "$YELLOW" "$NC"
        docker logs --tail 50 "$HERMES_CONTAINER" 2>&1 || true
    fi
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
        hermes config set model.provider openai-api \
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

install_9router() {
    clear_screen
    printf '%s--- Install / Reconfigure 9Router ---%s\n\n' \
        "$BOLD" "$NC"

    if ! ensure_docker; then
        return
    fi

    if container_exists "$NINEROUTER_CONTAINER"; then
        printf '%s[!] 9Router already exists.%s\n\n' "$YELLOW" "$NC"

        printf '1. Restart\n'
        printf '2. Reinstall / Reconfigure\n'
        printf '0. Cancel\n\n'

        printf 'Select [0-2]: '
        read -r option

        case "$option" in
            1)
                docker restart "$NINEROUTER_CONTAINER" >/dev/null

                printf '%s[✓] 9Router restarted.%s\n' \
                    "$GREEN" "$NC"

                return
                ;;
            2)
                docker rm -f "$NINEROUTER_CONTAINER" \
                    >/dev/null 2>&1 || true
                ;;
            0|*)
                return
                ;;
        esac
    fi

    printf 'Enter 9Router port [default: %s]: ' "$NINEROUTER_PORT"
    read -r requested_port

    if [ -n "$requested_port" ]; then
        NINEROUTER_PORT="$requested_port"
    fi

    case "$NINEROUTER_PORT" in
        ''|*[!0-9]*)
            printf '%s[✗] Invalid port.%s\n' "$RED" "$NC"
            return
            ;;
    esac

    if [ "$NINEROUTER_PORT" -lt 1 ] ||
       [ "$NINEROUTER_PORT" -gt 65535 ]; then

        printf '%s[✗] Port must be between 1 and 65535.%s\n' \
            "$RED" "$NC"

        return
    fi

    printf 'Enter 9Router password [default: %s]: ' "$NINEROUTER_PASSWORD"
    read -r requested_password

    if [ -n "$requested_password" ]; then
        NINEROUTER_PASSWORD="$requested_password"
    fi

    save_config

    printf '%s[*] Pulling 9Router image...%s\n' "$BLUE" "$NC"

    if ! docker pull "$NINEROUTER_IMAGE"; then
        printf '%s[✗] Failed to pull 9Router image.%s\n' \
            "$RED" "$NC"
        return
    fi

    printf '%s[*] Starting 9Router...%s\n' "$BLUE" "$NC"

    if ! docker run -d \
        --name "$NINEROUTER_CONTAINER" \
        --restart unless-stopped \
        -p "${NINEROUTER_PORT}:20128" \
        -v "${NINEROUTER_DATA_DIR}:/app/data" \
        -e DATA_DIR=/app/data \
        -e PORT=20128 \
        -e HOSTNAME=0.0.0.0 \
        -e INITIAL_PASSWORD="$NINEROUTER_PASSWORD" \
        "$NINEROUTER_IMAGE"; then

        printf '%s[✗] Failed to start 9Router.%s\n' \
            "$RED" "$NC"

        return
    fi

    sleep 4

    if container_running "$NINEROUTER_CONTAINER"; then
        daytona_id="$(get_daytona_id)"

        printf '%s[✓] 9Router is running.%s\n\n' \
            "$GREEN" "$NC"

        router_ip="$(get_container_ip "$NINEROUTER_CONTAINER")"
        router_host="${router_ip:-localhost}"

        printf '  Dashboard:\n'
        printf '  %shttp://%s:%s%s\n\n' \
            "$CYAN" "$router_host" "$NINEROUTER_PORT" "$NC"

        printf '  Daytona public URL:\n'
        printf '  %shttps://%s-%s.proxy.daytona.work%s\n\n' \
            "$CYAN" "$NINEROUTER_PORT" "$daytona_id" "$NC"

        printf '  OpenAI-compatible API:\n'
        printf '  %shttp://%s:%s/v1%s\n' \
            "$CYAN" "$router_host" "$NINEROUTER_PORT" "$NC"
        printf '  %shttps://%s-%s.proxy.daytona.work/v1%s\n' \
            "$CYAN" "$NINEROUTER_PORT" "$daytona_id" "$NC"
    else
        printf '%s[✗] 9Router stopped after startup.%s\n' \
            "$RED" "$NC"

        docker logs --tail 50 "$NINEROUTER_CONTAINER" 2>&1 || true
    fi
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

install_freellmapi() {
    clear_screen
    printf '%s--- Install / Reconfigure FreeLLMAPI ---%s\n\n' \
        "$BOLD" "$NC"

    if ! ensure_docker; then
        return
    fi

    load_config

    if container_exists "$FREELLMAPI_CONTAINER"; then
        printf '%s[!] FreeLLMAPI already exists.%s\n\n' "$YELLOW" "$NC"

        printf '1. Restart\n'
        printf '2. Reinstall / Reconfigure\n'
        printf '0. Cancel\n\n'

        printf 'Select [0-2]: '
        read -r option

        case "$option" in
            1)
                docker restart "$FREELLMAPI_CONTAINER" >/dev/null

                printf '%s[✓] FreeLLMAPI restarted.%s\n' \
                    "$GREEN" "$NC"

                return
                ;;
            2)
                docker rm -f "$FREELLMAPI_CONTAINER" \
                    >/dev/null 2>&1 || true
                ;;
            0|*)
                return
                ;;
        esac
    fi

    printf 'Enter FreeLLMAPI port [default: %s]: ' "$FREELLMAPI_PORT"
    read -r requested_port

    if [ -n "$requested_port" ]; then
        FREELLMAPI_PORT="$requested_port"
    fi

    case "$FREELLMAPI_PORT" in
        ''|*[!0-9]*)
            printf '%s[✗] Invalid port.%s\n' "$RED" "$NC"
            return
            ;;
    esac

    if [ "$FREELLMAPI_PORT" -lt 1 ] ||
       [ "$FREELLMAPI_PORT" -gt 65535 ]; then

        printf '%s[✗] Port must be between 1 and 65535.%s\n' \
            "$RED" "$NC"

        return
    fi

    if ! ensure_freellmapi_encryption_key; then
        return
    fi

    save_config

    printf '%s[*] Pulling FreeLLMAPI image...%s\n' "$BLUE" "$NC"

    if ! docker pull "$FREELLMAPI_IMAGE"; then
        printf '%s[✗] Failed to pull FreeLLMAPI image.%s\n' \
            "$RED" "$NC"
        return
    fi

    printf '%s[*] Starting FreeLLMAPI...%s\n' "$BLUE" "$NC"

    if ! docker run -d \
        --name "$FREELLMAPI_CONTAINER" \
        --restart unless-stopped \
        -p "${FREELLMAPI_PORT}:3001" \
        -v "${FREELLMAPI_DATA_DIR}:/app/server/data" \
        -e NODE_ENV=production \
        -e PORT=3001 \
        -e HOST_BIND=0.0.0.0 \
        -e ENCRYPTION_KEY="$FREELLMAPI_ENCRYPTION_KEY" \
        "$FREELLMAPI_IMAGE"; then

        printf '%s[✗] Failed to start FreeLLMAPI.%s\n' \
            "$RED" "$NC"

        return
    fi

    sleep 6

    if container_running "$FREELLMAPI_CONTAINER"; then
        daytona_id="$(get_daytona_id)"

        printf '%s[✓] FreeLLMAPI is running.%s\n\n' \
            "$GREEN" "$NC"

        freellmapi_ip="$(get_container_ip "$FREELLMAPI_CONTAINER")"
        freellmapi_host="${freellmapi_ip:-localhost}"

        printf '  Dashboard:\n'
        printf '  %shttp://%s:%s%s\n\n' \
            "$CYAN" "$freellmapi_host" "$FREELLMAPI_PORT" "$NC"

        printf '  Daytona public URL:\n'
        printf '  %shttps://%s-%s.proxy.daytona.work%s\n\n' \
            "$CYAN" "$FREELLMAPI_PORT" "$daytona_id" "$NC"

        printf '  OpenAI-compatible API:\n'
        printf '  %shttp://%s:%s/v1%s\n' \
            "$CYAN" "$freellmapi_host" "$FREELLMAPI_PORT" "$NC"
        printf '  %shttps://%s-%s.proxy.daytona.work/v1%s\n\n' \
            "$CYAN" "$FREELLMAPI_PORT" "$daytona_id" "$NC"

        printf '  First run: open the dashboard and create the admin\n'
        printf '  account (a one-time setup code is printed in the\n'
        printf '  container logs — menu option 7). Add provider keys\n'
        printf '  on the Keys page, then copy the unified API key.\n'
    else
        printf '%s[✗] FreeLLMAPI stopped after startup.%s\n' \
            "$RED" "$NC"

        docker logs --tail 50 "$FREELLMAPI_CONTAINER" 2>&1 || true
    fi
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
    printf '%s--- Hermes API Configuration ---%s\n\n' \
        "$BOLD" "$NC"

    load_config

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
# Container Logs
# ------------------------------------------------------------------------------

show_logs() {
    clear_screen
    printf '%s--- Container Logs ---%s\n\n' "$BOLD" "$NC"

    printf '1. Hermes\n'
    printf '2. 9Router\n'
    printf '3. FreeLLMAPI\n'
    printf '0. Cancel\n\n'

    printf 'Select [0-3]: '
    read -r option

    case "$option" in
        1)
            docker logs --tail 100 "$HERMES_CONTAINER" 2>&1
            ;;
        2)
            docker logs --tail 100 "$NINEROUTER_CONTAINER" 2>&1
            ;;
        3)
            docker logs --tail 100 "$FREELLMAPI_CONTAINER" 2>&1
            ;;
        0|*)
            return
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Execute Command in Container
# ------------------------------------------------------------------------------

exec_in_container() {
    clear_screen
    printf '%s--- Execute Command in Container ---%s\n\n' "$BOLD" "$NC"

    printf '1. Hermes\n'
    printf '2. 9Router\n'
    printf '3. FreeLLMAPI\n'
    printf '0. Cancel\n\n'

    printf 'Select [0-3]: '
    read -r target_option

    case "$target_option" in
        1) target_container="$HERMES_CONTAINER" ;;
        2) target_container="$NINEROUTER_CONTAINER" ;;
        3) target_container="$FREELLMAPI_CONTAINER" ;;
        0|*) return ;;
    esac

    if ! container_running "$target_container"; then
        printf '\n%s[✗] Container %s is not running.%s\n' "$RED" "$target_container" "$NC"
        return
    fi

    printf '\n%sOpening interactive shell in %s. Type "exit" to return to menu.%s\n\n' "$CYAN" "$target_container" "$NC"

    # Prefer bash for full readline/arrow support; fall back to sh
    if docker exec "$target_container" which bash >/dev/null 2>&1; then
        docker exec -it "$target_container" bash
    else
        docker exec -it "$target_container" sh
    fi
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
        return 1
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

# Probe google.com through the local HTTP inbound and compare with a direct call.
xray_test_latency() {
    if ! command -v curl >/dev/null 2>&1; then
        printf '%s[✗] curl is not available in this sandbox.%s\n' "$RED" "$NC"
        return 1
    fi

    if ! xray_core_running; then
        printf '%s[✗] The Xray core is not running. Start it first (option 5).%s\n' \
            "$RED" "$NC"
        return 1
    fi

    printf '\n%s[*] Testing %s through %s...%s\n\n' \
        "$BOLD" "$XRAY_TEST_URL" "$XRAY_PROXY_URL" "$NC"

    _xt_result="$(curl -s -o /dev/null \
        --proxy "$XRAY_PROXY_URL" \
        --connect-timeout 10 \
        --max-time 25 \
        -w '%{http_code} %{time_total}' \
        "$XRAY_TEST_URL" 2>&1)"
    _xt_status=$?

    if [ "$_xt_status" -ne 0 ]; then
        printf '%s[✗] Proxy request failed.%s\n' "$RED" "$NC"

        if [ -n "$_xt_result" ]; then
            printf '  %s%s%s\n' "$YELLOW" "$_xt_result" "$NC"
        fi

        printf '  The core is up, but the node is down, blocked or misconfigured.\n'
        return 1
    fi

    _xt_code="${_xt_result%% *}"
    _xt_total="${_xt_result#* }"
    _xt_total="${_xt_total%% *}"
    _xt_ms="$(xray_seconds_to_ms "$_xt_total")"

    _xt_ip="$(curl -s \
        --proxy "$XRAY_PROXY_URL" \
        --connect-timeout 10 \
        --max-time 20 \
        "$XRAY_TEST_IP_URL" 2>/dev/null || true)"

    _xt_direct="$(curl -s -o /dev/null \
        --noproxy '*' \
        --connect-timeout 10 \
        --max-time 25 \
        -w '%{time_total}' \
        "$XRAY_TEST_URL" 2>/dev/null || true)"

    _xt_direct_ms=""
    _xt_delta=""

    if [ -n "$_xt_direct" ]; then
        _xt_direct_ms="$(xray_seconds_to_ms "$_xt_direct")"
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
        printf '%s[!] The Xray core is not running, traffic stays blocked until it starts.%s\n' \
            "$YELLOW" "$NC"
    fi

    xray_set_system_proxy
    return 0
}

# ------------------------------------------------------------------------------
# Xray Menu
# ------------------------------------------------------------------------------

xray_menu() {
    while true; do
        clear_screen
        load_config

        if xray_core_running; then
            xray_core_state="${GREEN}Running${NC}"
        elif xray_core_installed; then
            xray_core_state="${YELLOW}Stopped${NC}"
        else
            xray_core_state="${RED}Not installed${NC}"
        fi

        if xray_proxy_enabled; then
            xray_proxy_state="${GREEN}Enabled${NC}"
        else
            xray_proxy_state="${YELLOW}Disabled${NC}"
        fi

        printf '%s--- Xray Proxy ---%s\n\n' "$BOLD" "$NC"

        printf '  Core:          %s\n' "$xray_core_state"
        printf '  System proxy:  %s\n' "$xray_proxy_state"

        if [ -n "$XRAY_NODE_LABEL" ]; then
            printf '  Node:          %s%s%s\n' \
                "$CYAN" "$XRAY_NODE_LABEL" "$NC"
        else
            printf '  Node:          %snone%s\n' "$YELLOW" "$NC"
        fi

        if [ -f "$XRAY_CONFIG_FILE" ]; then
            printf '  SOCKS:         %s%s%s\n' "$CYAN" "$XRAY_SOCKS_URL" "$NC"
            printf '  HTTP:          %s%s%s\n' "$CYAN" "$XRAY_PROXY_URL" "$NC"
        fi

        printf '\n'
        printf '1. Add / Change node link\n'
        printf '2. Pause / Resume system proxy\n'
        printf '\n'
        printf '3. Restart core\n'
        printf '4. Stop core\n'
        printf '5. Start core\n'
        printf '\n'
        printf '6. Test proxy latency\n'
        printf '7. Show Xray logs\n'
        printf '8. Show Xray client config\n'
        printf '\n'
        printf '0. Back\n'

        printf '\n%s───────────────────────────────────────────────────────────────────────────%s\n\n' \
            "$CYAN" "$NC"

        printf 'Select an option [0-8]: '
        read -r xray_choice

        case "$xray_choice" in
            1) xray_add_node ;;
            2) xray_toggle_proxy ;;
            3)
                if ensure_docker && xray_core_restart; then
                    printf '\n%s[✓] Xray core restarted.%s\n' "$GREEN" "$NC"
                fi
                ;;
            4)
                if ensure_docker; then
                    xray_core_stop
                fi
                ;;
            5)
                if ensure_docker && xray_core_start; then
                    printf '\n%s[✓] Xray core is running.%s\n' "$GREEN" "$NC"
                fi
                ;;
            6) xray_test_latency ;;
            7)
                if ensure_docker && xray_core_installed; then
                    docker logs --tail 100 "$XRAY_CONTAINER" 2>&1
                fi
                ;;
            8) xray_show_config ;;
            0) return ;;
            *) printf '%s[✗] Invalid option.%s\n' "$RED" "$NC" ;;
        esac

        printf '\nPress Enter to return to the Xray menu...'
        read -r xray_dummy
    done
}

# ------------------------------------------------------------------------------
# Main Menu Loop
# ------------------------------------------------------------------------------

while true; do
    clear_screen

    render_banner
    render_status

    printf '%s───────────────────────────────────────────────────────────────────────────%s\n' \
        "$CYAN" "$NC"

    printf '\n'
    printf '1. Install / Reinstall Hermes\n'
    printf '2. Install / Reconfigure 9Router\n'
    printf '3. Install / Reconfigure FreeLLMAPI\n'
    printf '\n'
    printf '4. Set Hermes API endpoint and token\n'
    printf '5. Set Hermes Telegram bot token and allowed users\n'
    printf '\n'
    printf '6. Show Hermes configuration\n'
    printf '7. Show container logs\n'
    printf '\n'
    printf '8. Execute command inside container\n'
    printf '\n'
    printf '9. Xray proxy (node / system proxy / core / latency)\n'
    printf '\n'
    printf '0. Exit\n'

    printf '\n%s───────────────────────────────────────────────────────────────────────────%s\n\n' \
        "$CYAN" "$NC"

    printf 'Select an option [0-9]: '
    read -r choice

    case "$choice" in
        1) install_hermes ;;
        2) install_9router ;;
        3) install_freellmapi ;;
        4) set_hermes_api ;;
        5) set_telegram ;;
        6) show_hermes_config ;;
        7) show_logs ;;
        8) exec_in_container ;;
        9) xray_menu ;;
        0) printf '%sExiting.%s\n' "$GREEN" "$NC"; exit 0 ;;
        *) printf '%s[✗] Invalid option.%s\n' "$RED" "$NC" ;;
    esac

    printf '\nPress Enter to return to the menu...'
    read -r dummy
done