# Hermes Agent & 9Router on Daytona

An interactive management CLI and deployment toolkit for orchestrating Hermes Agent and 9Router inside a Daytona Docker-in-Docker (DinD) sandbox with Telegram gateway integration.

---

## Overview

* **Daytona Sandbox:** Docker-in-Docker environment (`docker:29.4-dind`).
* **Hermes Agent:** Autonomous AI agent operating in an isolated container.
* **Telegram Gateway:** Direct two-way messaging channel with user ID whitelisting.
* **9Router:** Local/public OpenAI-compatible API gateway.
* **TUI Console (`install.sh`):** Interactive terminal interface with live status checks, masked secrets, and automatic Daytona proxy URL discovery.

---

## Prerequisites

* Daytona Sandbox booted with a DinD image (e.g., `docker:29.4-dind`).
* Recommended resources: 2 vCPU, 4 GB RAM, 10 GB disk.
* Telegram Bot Token from [@BotFather](https://t.me/BotFather).
* Your numeric Telegram User ID.

---

## Installation & Usage

Run the bootstrap command inside your Daytona sandbox terminal:

```bash
wget -qO install.sh "https://raw.githubusercontent.com/WhoisNeon/Daytona-Hermes/main/install.sh?$(date +%s)" && sh install.sh
```

---

## Interactive Menu

Upon launch, `install.sh` displays the dynamic ASCII art banner and a live status overview:

```text
  _    _                                   ___  _____ 
 | |  | |                                 / _ \|  _  |
 | |__| | ___ _ __ _ __ ___   ___  ___   / /_\ \ |_/ /
 |  __  |/ _ \ '__| '_ ` _ \ / _ \/ __|  |  _  |  __/ 
 | |  | |  __/ |  | | | | | |  __/\__ \  | | | | |    
 |_|  |_|\___|_|  |_| |_| |_|\___||___/  \_| |_/\_|    
       Daytona Sandbox Edition  •  By @WhoisNeon

Component Status:

  Hermes installed:          Yes (Running)
  Hermes API endpoint:       https://9router.example.com/v1
  Hermes API token:          sk-3•••••••••••••••••••••••••634f
  Telegram bot token:        123456789:AAa••••••••••••••••••••••••••••xyz
  Allowed users:             123456789

  9Router installed:         Yes (Running)
  9Router port:              20128
  9Router local URL:         http://localhost:20128
  9Router public URL:        https://20128-<UUID>.proxy.daytona.work

--------------------------------------------------------

1. Install Hermes
2. Install 9Router
3. Set Hermes API endpoint and API token
4. Set Hermes Telegram bot token and allowed users
5. Show Hermes configuration
6. Exit

--------------------------------------------------------
```

### Options Breakdown

1. **Install Hermes:** Clones the template, configures local host persistence at `/data/hermes`, builds the container, and boots Hermes with custom parameters.


2. **Install 9Router:** Sets the listening port (default: `20128`), checks port availability, starts the container, and exposes public/local proxy URLs.
3. **Set Hermes API endpoint and API token:** Updates target OpenAI-compatible endpoint and access keys without printing raw secrets.
4. **Set Hermes Telegram bot token and allowed users:** Configures Telegram bot credentials and permitted user IDs.


5. **Show Hermes configuration:** Inspects and returns runtime parameters from the running container.
6. **Exit:** Safely exits the management console.

---

## Endpoint Resolution

When 9Router is active, URLs resolve dynamically using your Daytona Sandbox UUID:

* **Local Loopback:** `http://localhost:<PORT>`
* **Daytona Public Proxy:** `https://<PORT>-<SANDBOX_UUID>.proxy.daytona.work`

---

## Data Persistence

* Hermes state, vector stores, skills, session history, and configurations are saved to `/data/hermes` on the host.


* The container maps this directory to `/data`. Container upgrades and restarts retain all runtime data.

---

## Troubleshooting

* **Docker Socket Error (`Cannot connect to the Docker daemon`):** Ensure the sandbox was created with a Docker-in-Docker template. Check daemon status using `ps aux | grep '[d]ockerd'`.


* **Telegram Not Responding:** Verify that your ID in `Allowed users` is numeric and comma-separated (e.g., `123456789,987654321`). Inspect live gateway events:


```bash
docker exec -it hermes tail -f /data/.hermes/logs/gateways/default/current
```

---

## License

This project is licensed under the [`MIT License`](LICENSE).