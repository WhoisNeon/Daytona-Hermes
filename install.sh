#!/bin/sh

set -u

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------

BASE_DIR="${HOME}/hermes-manager"
CONFIG_FILE="${BASE_DIR}/config.env"

HERMES_DATA_DIR="/data/hermes"
NINEROUTER_DATA_DIR="${BASE_DIR}/9router-data"

HERMES_REPO_URL="https://github.com/lovexbytes/hermes-railway-template/archive/refs/heads/main.tar.gz"
HERMES_REPO_DIR="${BASE_DIR}/hermes-railway-template"

HERMES_CONTAINER="hermes"
NINEROUTER_CONTAINER="9router"

NINEROUTER_IMAGE="ghcr.io/neon-2026/9router:usage-backup"
DEFAULT_NINEROUTER_PORT="20128"

mkdir -p "$BASE_DIR"
mkdir -p "$HERMES_DATA_DIR"
mkdir -p "$NINEROUTER_DATA_DIR"

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
# Banner
# ------------------------------------------------------------------------------

render_banner() {
    printf '%s%s\n' "$CYAN" "$BOLD"
    printf '  _    _                                   ___  _____\n'
    printf ' | |  | |                                 / _ \\|  _  |\n'
    printf ' | |__| | ___ _ __ _ __ ___   ___  ___   / /_\\ \\ |_/ /\n'
    printf ' |  __  |/ _ \\ '\''__| '\''_ \\ _ \\ / _ \\/ __|  |  _  |  __/\n'
    printf ' | |  | |  __/ |  | | | | | |  __/\\__ \\  | | | | |\n'
    printf ' |_|  |_|\\___|_|  |_| |_| |_|\\___||___/  \\_| |_/\\_|\n'
    printf '\n'
    printf '       Daytona Sandbox Edition • By @WhoisNeon\n'
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

    # Telegram:
    # 123456789:ABCDEF...
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

    if container_running "$NINEROUTER_CONTAINER"; then
        router_status="${GREEN}Running${NC}"
    elif container_exists "$NINEROUTER_CONTAINER"; then
        router_status="${YELLOW}Stopped${NC}"
    else
        router_status="${RED}Not installed${NC}"
    fi

    daytona_id="$(get_daytona_id)"

    printf '%s%sStatus%s\n\n' "$BOLD" "$CYAN" "$NC"

    printf '  Hermes:                    %s\n' "$hermes_status"

    printf '  Hermes API endpoint:       %s%s%s\n' \
        "$CYAN" "${HERMES_API_URL:-Not set}" "$NC"

    printf '  Hermes API token:          %s%s%s\n' \
        "$CYAN" "$(redact_secret "${HERMES_API_TOKEN:-}")" "$NC"

    printf '  Telegram bot token:        %s%s%s\n' \
        "$CYAN" "$(redact_secret "${TELEGRAM_BOT_TOKEN:-}")" "$NC"

    printf '  Telegram allowed users:    %s%s%s\n' \
        "$CYAN" "${TELEGRAM_ALLOWED_USERS:-Not set}" "$NC"

    printf '\n'

    printf '  9Router:                   %s\n' "$router_status"

    printf '  9Router port:              %s%s%s\n' \
        "$CYAN" "$NINEROUTER_PORT" "$NC"

    printf '  9Router local URL:         %shttp://localhost:%s%s\n' \
        "$CYAN" "$NINEROUTER_PORT" "$NC"

    printf '  9Router public URL:        %shttps://%s-%s.proxy.daytona.work%s\n' \
        "$CYAN" "$NINEROUTER_PORT" "$daytona_id" "$NC"

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
    printf '\n%s--- Install Hermes ---%s\n\n' "$BOLD" "$NC"

    if ! ensure_docker; then
        return
    fi

    if container_exists "$HERMES_CONTAINER"; then
        printf '%s[!] Hermes already exists.%s\n\n' "$YELLOW" "$NC"

        printf '1. Restart\n'
        printf '2. Rebuild\n'
        printf '3. Cancel\n\n'

        printf 'Select [1-3]: '
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
            *)
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
        hermes config set model.provider custom \
        >/dev/null 2>&1 || true

    docker exec "$HERMES_CONTAINER" \
        hermes config set model.base_url "$HERMES_API_URL" \
        >/dev/null 2>&1 || true

    docker exec "$HERMES_CONTAINER" \
        hermes config set model.api_key "$HERMES_API_TOKEN" \
        >/dev/null 2>&1 || true

    docker exec "$HERMES_CONTAINER" \
        hermes config set model.default "$HERMES_MODEL" \
        >/dev/null 2>&1 || true
}

# ------------------------------------------------------------------------------
# 9Router
# ------------------------------------------------------------------------------

install_9router() {
    printf '\n%s--- Install / Reconfigure 9Router ---%s\n\n' \
        "$BOLD" "$NC"

    if ! ensure_docker; then
        return
    fi

    if container_exists "$NINEROUTER_CONTAINER"; then
        printf '%s[!] 9Router already exists.%s\n\n' "$YELLOW" "$NC"

        printf '1. Restart\n'
        printf '2. Reinstall\n'
        printf '3. Cancel\n\n'

        printf 'Select [1-3]: '
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
            *)
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

        printf '  Dashboard:\n'
        printf '  %shttp://localhost:%s%s\n\n' \
            "$CYAN" "$NINEROUTER_PORT" "$NC"

        printf '  Daytona public URL:\n'
        printf '  %shttps://%s-%s.proxy.daytona.work%s\n\n' \
            "$CYAN" "$NINEROUTER_PORT" "$daytona_id" "$NC"

        printf '  OpenAI-compatible API:\n'
        printf '  %shttp://localhost:%s/v1%s\n' \
            "$CYAN" "$NINEROUTER_PORT" "$NC"
    else
        printf '%s[✗] 9Router stopped after startup.%s\n' \
            "$RED" "$NC"

        docker logs --tail 50 "$NINEROUTER_CONTAINER" 2>&1 || true
    fi
}

# ------------------------------------------------------------------------------
# Hermes API Settings
# ------------------------------------------------------------------------------

set_hermes_api() {
    printf '\n%s--- Hermes API Configuration ---%s\n\n' \
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

    configure_hermes_inside_container

    printf '\n%s[✓] Hermes API configuration saved.%s\n' \
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
    printf '\n%s--- Hermes Telegram Configuration ---%s\n\n' \
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

    if container_running "$HERMES_CONTAINER"; then
        printf '%s[*] Restarting Hermes...%s\n' "$BLUE" "$NC"

        docker restart "$HERMES_CONTAINER" >/dev/null 2>&1

        printf '%s[✓] Telegram configuration applied.%s\n' \
            "$GREEN" "$NC"
    else
        printf '%s[✓] Telegram configuration saved.%s\n' \
            "$GREEN" "$NC"
    fi
}

# ------------------------------------------------------------------------------
# Show Hermes Config
# ------------------------------------------------------------------------------

show_hermes_config() {
    printf '\n%s================ Hermes Configuration ================%s\n\n' \
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
    printf '\n%s--- Container Logs ---%s\n\n' "$BOLD" "$NC"

    printf '1. Hermes\n'
    printf '2. 9Router\n'
    printf '3. Cancel\n\n'

    printf 'Select [1-3]: '
    read -r option

    case "$option" in
        1)
            docker logs --tail 100 "$HERMES_CONTAINER" 2>&1
            ;;
        2)
            docker logs --tail 100 "$NINEROUTER_CONTAINER" 2>&1
            ;;
        *)
            return
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Main Menu
# ------------------------------------------------------------------------------

while true; do
    clear 2>/dev/null || true

    render_banner
    render_status

    printf '%s--------------------------------------------------------%s\n' \
        "$CYAN" "$NC"

    printf '\n'
    printf '1. Install / Reinstall Hermes\n'
    printf '2. Install / Reconfigure 9Router\n'
    printf '3. Set Hermes API endpoint and token\n'
    printf '4. Set Hermes Telegram bot token and allowed users\n'
    printf '5. Show Hermes configuration\n'
    printf '6. Show container logs\n'
    printf '7. Exit\n'

    printf '\n%s--------------------------------------------------------%s\n\n' \
        "$CYAN" "$NC"

    printf 'Select an option [1-7]: '
    read -r choice

    case "$choice" in
        1) install_hermes ;;
        2) install_9router ;;
        3) set_hermes_api ;;
        4) set_telegram ;;
        5) show_hermes_config ;;
        6) show_logs ;;
        7) printf '%sExiting.%s\n' "$GREEN" "$NC"; exit 0 ;;
        *) printf '%s[✗] Invalid option.%s\n' "$RED" "$NC" ;;
    esac

    printf '\nPress Enter to return to the menu...'
    read -r dummy
done