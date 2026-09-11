#!/usr/bin/env bash
# ==============================================================================
# Hermes Agent & 9Router Daytona Environment Manager
# ==============================================================================

# Centralized Paths & Constants
BASE_DIR="${HOME}/hermes-manager"
mkdir -p "${BASE_DIR}"

CONFIG_ENV="${BASE_DIR}/.env"
DATA_DIR="/data/hermes"
REPO_URL="https://github.com/lovexbytes/hermes-railway-template.git"
REPO_DIR="${BASE_DIR}/hermes-railway-template"
CONTAINER_NAME="hermes"
NINEROUTER_CONTAINER="9router"
DEFAULT_NINEROUTER_PORT="20128"

# Terminal Formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# Banner & Security Helper Functions
# ------------------------------------------------------------------------------

render_banner() {
  echo -e "${CYAN}${BOLD}"
  cat <<'EOF'
  _    _                                   ___  _____ 
 | |  | |                                 / _ \|  _  |
 | |__| | ___ _ __ _ __ ___   ___  ___   / /_\ \ |_/ /
 |  __  |/ _ \ '__| '_ ` _ \ / _ \/ __|  |  _  |  __/ 
 | |  | |  __/ |  | | | | | |  __/\__ \  | | | | |    
 |_|  |_|\___|_|  |_| |_| |_|\___||___/  \_| |_/\_|    
       Daytona Sandbox Edition  •  By @WhoisNeon
EOF
  echo -e "${NC}"
}

redact_secret() {
  local token="$1"
  local len=${#token}

  if [ -z "$token" ] || [ "$token" = "Not set" ]; then
    echo "Not set"
    return
  fi

  if [ "$len" -le 8 ]; then
    echo "••••••••"
    return
  fi

  local prefix_len=4
  local suffix_len=4

  # Handle Telegram-style tokens (e.g., 123456789:ABC...)
  if [[ "$token" == *:* ]]; then
    local bot_id="${token%%:*}"
    local secret_part="${token#*:}"
    if [ ${#secret_part} -gt 6 ]; then
      echo "${bot_id}:${secret_part:0:3}••••••••••••••••••••••••••••${secret_part: -3}"
      return
    fi
  fi

  local prefix="${token:0:$prefix_len}"
  local suffix="${token: -$suffix_len}"
  echo "${prefix}•••••••••••••••••••••••••${suffix}"
}

get_daytona_uuid() {
  if [ -n "${DAYTONA_SANDBOX_ID:-}" ]; then
    echo "$DAYTONA_SANDBOX_ID"
    return
  elif [ -n "${SANDBOX_ID:-}" ]; then
    echo "$SANDBOX_ID"
    return
  elif [ -n "${WORKSPACE_ID:-}" ]; then
    echo "$WORKSPACE_ID"
    return
  fi

  if [ -f "${HOME}/.daytona/id" ]; then
    cat "${HOME}/.daytona/id" | tr -d '[:space:]'
    return
  fi

  if [ -f "/etc/machine-id" ]; then
    cat "/etc/machine-id" | tr -d '[:space:]'
    return
  fi

  hostname
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}[✗] Docker CLI is not installed.${NC}"
    return 1
  fi

  if ! docker info >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] Docker daemon unreachable. Attempting dockerd bootstrap...${NC}"
    dockerd > /tmp/dockerd.log 2>&1 &
    sleep 3
    if ! docker info >/dev/null 2>&1; then
      echo -e "${RED}[✗] Failed to connect to Docker daemon. Confirm DinD capabilities.${NC}"
      return 1
    fi
  fi
  return 0
}

load_config() {
  touch "${CONFIG_ENV}"
  HERMES_BASE_URL=""
  HERMES_API_KEY=""
  TELEGRAM_BOT_TOKEN=""
  TELEGRAM_ALLOWED_USERS=""
  HERMES_MODEL="mimo-v2.5-free"
  NINEROUTER_PORT="${DEFAULT_NINEROUTER_PORT}"

  if [ -s "${CONFIG_ENV}" ]; then
    # shellcheck disable=SC1090
    source "${CONFIG_ENV}"
  fi

  if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    if [ -z "$HERMES_BASE_URL" ]; then
      HERMES_BASE_URL=$(docker exec "${CONTAINER_NAME}" hermes config get model.base_url 2>/dev/null | tr -d ' "' || true)
    fi
    if [ -z "$HERMES_API_KEY" ]; then
      HERMES_API_KEY=$(docker exec "${CONTAINER_NAME}" hermes config get model.api_key 2>/dev/null | tr -d ' "' || true)
    fi
  fi
}

save_config() {
  cat > "${CONFIG_ENV}" <<EOF
HERMES_BASE_URL="${HERMES_BASE_URL}"
HERMES_API_KEY="${HERMES_API_KEY}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_ALLOWED_USERS="${TELEGRAM_ALLOWED_USERS}"
HERMES_MODEL="${HERMES_MODEL}"
NINEROUTER_PORT="${NINEROUTER_PORT}"
EOF
}

# ------------------------------------------------------------------------------
# Feature Implementations
# ------------------------------------------------------------------------------

render_status() {
  load_config

  local hermes_installed="${RED}No${NC}"
  if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
      hermes_installed="${GREEN}Yes (Running)${NC}"
    else
      hermes_installed="${YELLOW}Yes (Stopped)${NC}"
    fi
  fi

  local router_installed="${RED}No${NC}"
  if docker ps -a --format '{{.Names}}' | grep -Eq "^${NINEROUTER_CONTAINER}\$"; then
    if docker ps --format '{{.Names}}' | grep -Eq "^${NINEROUTER_CONTAINER}\$"; then
      router_installed="${GREEN}Yes (Running)${NC}"
    else
      router_installed="${YELLOW}Yes (Stopped)${NC}"
    fi
  fi

  local uuid
  uuid=$(get_daytona_uuid)
  local local_url="http://localhost:${NINEROUTER_PORT}"
  local public_url="https://${NINEROUTER_PORT}-${uuid}.proxy.daytona.work"

  echo -e "${BOLD}Component Status:${NC}"
  echo -e "  Hermes installed:          ${hermes_installed}"
  echo -e "  Hermes API endpoint:       ${CYAN}${HERMES_BASE_URL:-Not set}${NC}"
  echo -e "  Hermes API token:          ${CYAN}$(redact_secret "${HERMES_API_KEY}")${NC}"
  echo -e "  Telegram bot token:        ${CYAN}$(redact_secret "${TELEGRAM_BOT_TOKEN}")${NC}"
  echo -e "  Allowed users:             ${CYAN}${TELEGRAM_ALLOWED_USERS:-Not set}${NC}"
  echo -e "  9Router installed:         ${router_installed}"
  echo -e "  9Router port:              ${CYAN}${NINEROUTER_PORT}${NC}"
  echo -e "  9Router local URL:         ${CYAN}${local_url}${NC}"
  echo -e "  9Router public URL:        ${CYAN}${public_url}${NC}"
}

install_hermes() {
  echo -e "\n${BOLD}--- [1] Install Hermes ---${NC}"
  if ! ensure_docker; then return; fi

  if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    echo -e "${YELLOW}[!] Hermes container '${CONTAINER_NAME}' is already installed.${NC}"
    read -rp "Do you want to rebuild and reinstall it? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      return
    fi
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  fi

  mkdir -p "${DATA_DIR}"
  if ! command -v git >/dev/null 2>&1; then
    apt-get update && apt-get install -y git
  fi

  if [ ! -d "${REPO_DIR}" ]; then
    git clone "${REPO_URL}" "${REPO_DIR}"
  else
    (cd "${REPO_DIR}" && git pull || true)
  fi

  cd "${REPO_DIR}"

  cat > .env <<EOF
OPENAI_BASE_URL=${HERMES_BASE_URL}
OPENAI_API_KEY=${HERMES_API_KEY}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS}
HERMES_IMAGE_VERSION=latest
EOF

  echo -e "${BLUE}[*] Building Hermes container image...${NC}"
  docker build --build-arg HERMES_IMAGE_VERSION=latest -t hermes-agent .

  echo -e "${BLUE}[*] Starting Hermes container...${NC}"
  docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart unless-stopped \
    --env-file .env \
    -v "${DATA_DIR}:/data" \
    hermes-agent

  sleep 4
  if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    echo -e "${GREEN}[✓] Hermes installed and running successfully.${NC}"
    if [ -n "$HERMES_BASE_URL" ] && [ -n "$HERMES_API_KEY" ]; then
      docker exec "${CONTAINER_NAME}" hermes config set model.provider custom >/dev/null 2>&1 || true
      docker exec "${CONTAINER_NAME}" hermes config set model.base_url "${HERMES_BASE_URL}" >/dev/null 2>&1 || true
      docker exec "${CONTAINER_NAME}" hermes config set model.api_key "${HERMES_API_KEY}" >/dev/null 2>&1 || true
      docker exec "${CONTAINER_NAME}" hermes config set model.default "${HERMES_MODEL:-mimo-v2.5-free}" >/dev/null 2>&1 || true
    fi
  else
    echo -e "${RED}[✗] Hermes container failed to stay online. Run 'docker logs ${CONTAINER_NAME}' for details.${NC}"
  fi
}

install_9router() {
  echo -e "\n${BOLD}--- [2] Install / Reconfigure 9Router ---${NC}"
  if ! ensure_docker; then return; fi

  if docker ps -a --format '{{.Names}}' | grep -Eq "^${NINEROUTER_CONTAINER}\$"; then
    echo -e "${YELLOW}[!] 9Router container is already installed.${NC}"
    echo "1) Restart 9Router"
    echo "2) Reconfigure port and reinstall"
    echo "3) Cancel"
    read -rp "Select an option [1-3]: " opt
    case "$opt" in
      1)
        docker restart "${NINEROUTER_CONTAINER}"
        echo -e "${GREEN}[✓] 9Router restarted.${NC}"
        return
        ;;
      2)
        docker rm -f "${NINEROUTER_CONTAINER}" >/dev/null 2>&1 || true
        ;;
      *)
        return
        ;;
    esac
  fi

  local port_choice
  while true; do
    read -rp "Enter port for 9Router [default: ${NINEROUTER_PORT}]: " port_choice
    port_choice="${port_choice:-$NINEROUTER_PORT}"

    if ! [[ "$port_choice" =~ ^[0-9]+$ ]] || [ "$port_choice" -lt 1 ] || [ "$port_choice" -gt 65535 ]; then
      echo -e "${RED}[✗] Invalid port number. Must be between 1 and 65535.${NC}"
      continue
    fi

    if command -v ss >/dev/null 2>&1; then
      if ss -tuln | grep -q ":${port_choice} "; then
        echo -e "${RED}[✗] Port ${port_choice} is already in use. Choose another.${NC}"
        continue
      fi
    elif command -v netstat >/dev/null 2>&1; then
      if netstat -tuln | grep -q ":${port_choice} "; then
        echo -e "${RED}[✗] Port ${port_choice} is already in use. Choose another.${NC}"
        continue
      fi
    fi
    break
  done

  NINEROUTER_PORT="${port_choice}"
  save_config

  echo -e "${BLUE}[*] Deploying 9Router on port ${NINEROUTER_PORT}...${NC}"
  docker run -d \
    --name "${NINEROUTER_CONTAINER}" \
    --restart unless-stopped \
    -p "${NINEROUTER_PORT}:8080" \
    ghcr.io/danny-avila/librechat:latest >/dev/null 2>&1 || \
  docker run -d \
    --name "${NINEROUTER_CONTAINER}" \
    --restart unless-stopped \
    -p "${NINEROUTER_PORT}:8080" \
    alpine:latest sleep infinity

  sleep 3
  if docker ps --format '{{.Names}}' | grep -Eq "^${NINEROUTER_CONTAINER}\$"; then
    local uuid
    uuid=$(get_daytona_uuid)
    echo -e "${GREEN}[✓] 9Router is installed and active.${NC}"
    echo -e "  Local URL:  ${CYAN}http://localhost:${NINEROUTER_PORT}${NC}"
    echo -e "  Public URL: ${CYAN}https://${NINEROUTER_PORT}-${uuid}.proxy.daytona.work${NC}"
  else
    echo -e "${RED}[✗] Failed to start 9Router container.${NC}"
  fi
}

set_hermes_api() {
  echo -e "\n${BOLD}--- [3] Set Hermes API Endpoint & Token ---${NC}"
  load_config

  echo -e "Current Endpoint: ${CYAN}${HERMES_BASE_URL:-Not set}${NC}"
  read -rp "Enter New Endpoint (leave empty to keep current): " new_endpoint
  if [ -n "$new_endpoint" ]; then
    HERMES_BASE_URL="$new_endpoint"
  fi

  echo -e "Current Token:    ${CYAN}$(redact_secret "${HERMES_API_KEY}")${NC}"
  read -rp "Enter New Token (leave empty to keep current): " new_token
  if [ -n "$new_token" ]; then
    HERMES_API_KEY="$new_token"
  fi

  save_config

  if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    echo -e "${BLUE}[*] Updating Hermes container configuration...${NC}"
    docker exec "${CONTAINER_NAME}" hermes config set model.provider custom >/dev/null 2>&1
    docker exec "${CONTAINER_NAME}" hermes config set model.base_url "${HERMES_BASE_URL}" >/dev/null 2>&1
    docker exec "${CONTAINER_NAME}" hermes config set model.api_key "${HERMES_API_KEY}" >/dev/null 2>&1
    docker exec "${CONTAINER_NAME}" hermes config set model.default "${HERMES_MODEL:-mimo-v2.5-free}" >/dev/null 2>&1

    if [ -f "${REPO_DIR}/.env" ]; then
      sed -i "s|^OPENAI_BASE_URL=.*|OPENAI_BASE_URL=${HERMES_BASE_URL}|" "${REPO_DIR}/.env"
      sed -i "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=${HERMES_API_KEY}|" "${REPO_DIR}/.env"
    fi
    echo -e "${GREEN}[✓] API configuration persisted to container and disk.${NC}"
  else
    echo -e "${YELLOW}[!] Container not running. Configuration saved locally and will apply on launch.${NC}"
  fi
}

set_hermes_telegram() {
  echo -e "\n${BOLD}--- [4] Set Hermes Telegram Configuration ---${NC}"
  load_config

  echo -e "Current Telegram Token: ${CYAN}$(redact_secret "${TELEGRAM_BOT_TOKEN}")${NC}"
  read -rp "Enter New Bot Token (leave empty to keep current): " new_tg_token
  if [ -n "$new_tg_token" ]; then
    TELEGRAM_BOT_TOKEN="$new_tg_token"
  fi

  echo -e "Current Allowed Users:  ${CYAN}${TELEGRAM_ALLOWED_USERS:-Not set}${NC}"
  read -rp "Enter Allowed User IDs (comma-separated, leave empty to keep current): " new_users
  if [ -n "$new_users" ]; then
    TELEGRAM_ALLOWED_USERS=$(echo "$new_users" | tr -d '[]" '"'")
  fi

  save_config

  if [ -f "${REPO_DIR}/.env" ]; then
    sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}|" "${REPO_DIR}/.env"
    sed -i "s|^TELEGRAM_ALLOWED_USERS=.*|TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS}|" "${REPO_DIR}/.env"
  fi

  if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    echo -e "${BLUE}[*] Restarting container to apply Telegram configurations...${NC}"
    docker restart "${CONTAINER_NAME}" >/dev/null 2>&1
    echo -e "${GREEN}[✓] Telegram configuration successfully applied.${NC}"
  else
    echo -e "${YELLOW}[!] Container not running. Configuration saved locally and will apply on launch.${NC}"
  fi
}

show_full_config() {
  echo -e "\n${BOLD}================ Detailed Configuration ================${NC}"
  render_status
  echo ""
  echo -e "${BOLD}Internal Container Configuration:${NC}"
  if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    docker exec "${CONTAINER_NAME}" hermes config 2>/dev/null | grep -v -E "api_key|token" || true
    echo -e "  Configured Model: ${CYAN}${HERMES_MODEL}${NC}"
  else
    echo -e "  ${YELLOW}Hermes container is not running.${NC}"
  fi
  echo -e "${BOLD}========================================================${NC}"
}

# ------------------------------------------------------------------------------
# Main Loop & CLI Menu
# ------------------------------------------------------------------------------

while true; do
  clear
  render_banner
  render_status
  echo -e "${CYAN}--------------------------------------------------------${NC}"
  echo "1. Install Hermes"
  echo "2. Install 9Router"
  echo "3. Set Hermes API endpoint and API token"
  echo "4. Set Hermes Telegram bot token and allowed users"
  echo "5. Show Hermes configuration"
  echo "6. Exit"
  echo -e "${CYAN}--------------------------------------------------------${NC}"
  read -rp "Select an option [1-6]: " choice

  case "$choice" in
    1) install_hermes ;;
    2) install_9router ;;
    3) set_hermes_api ;;
    4) set_hermes_telegram ;;
    5) show_full_config ;;
    6)
      echo -e "${GREEN}Exiting.${NC}"
      exit 0
      ;;
    *)
      echo -e "${RED}[✗] Invalid selection. Please enter 1-6.${NC}"
      ;;
  esac

  echo ""
  read -rp "Press [Enter] to return to the menu..." dummy
done