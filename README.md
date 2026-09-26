# Hermes Agent & 9Router & FreeLLMAPI on Daytona

An interactive management CLI and deployment toolkit for orchestrating Hermes Agent and 9Router inside a Daytona Docker-in-Docker (DinD) sandbox with Telegram gateway integration.

---

## Overview

* **Daytona Sandbox:** Docker-in-Docker environment (`docker:29.4-dind`).
* **Hermes Agent:** Autonomous AI agent operating in an isolated container with local persistence.
* **Telegram Gateway:** Direct two-way messaging channel with user ID whitelisting.
* **9Router:** Local/public OpenAI-compatible API gateway and management dashboard.
* **FreeLLMAPI:** Local/public OpenAI-compatible gateway aggregating 34+ free LLM providers (635+ model endpoints) behind one `/v1` endpoint with smart routing and automatic failover ([tashfeenahmed/freellmapi](https://github.com/tashfeenahmed/freellmapi)).
* **TUI Console (`install.sh`):** Interactive terminal interface with live status checks, masked secrets, automated daemon recovery, log inspection, and Daytona proxy URL discovery.

---

## Prerequisites

* [Daytona Sandbox](https://app.daytona.io/dashboard/sandboxes) booted with a DinD image (e.g., `docker:29.4-dind`).
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

Upon launch, `install.sh` displays the dynamic ASCII banner alongside a real-time status summary:

```text
  _   _                                    _                    _   
 | | | | ___ _ __ _ __ ___   ___  ___     / \   __ _  ___ _ __ | |_ 
 | |_| |/ _ \ '__| '_ ` _ \ / _ \/ __|   / _ \ / _` |/ _ \ '_ \| __|
 |  _  |  __/ |  | | | | | |  __/\__ \  / ___ \ (_| |  __/ | | | |_ 
 |_| |_|\___|_|  |_| |_| |_|\___||___/ /_/   \_\__, |\___|_| |_|\__|
                                               |___/                

       Daytona Sandbox Edition • By WhoisNeon • v1.x.x

───────────────────────────────────────────────────────────────────────────

Status

  Hermes:                    Running
  Hermes API endpoint:       http://<CONTAINER_IP>:20128/v1
  Hermes API token:          sk-3•••••••••••••••••••••••••634f

  Telegram bot token:        123456789:AAa••••••••••••••••••••••••••••xyz
  Telegram allowed users:    123456789

  9Router:                   Running
  9Router port:              20128
  9Router local URL:         http://<CONTAINER_IP>:20128
  9Router public URL:        https://20128-<SANDBOX_ID>.proxy.daytona.work

  FreeLLMAPI:                Running
  FreeLLMAPI port:           3001
  FreeLLMAPI local URL:      http://<CONTAINER_IP>:3001
  FreeLLMAPI public URL:     https://3001-<SANDBOX_ID>.proxy.daytona.work

───────────────────────────────────────────────────────────────────────────

1. Install / Reinstall Hermes
2. Install / Reconfigure 9Router
3. Install / Reconfigure FreeLLMAPI

4. Set Hermes API endpoint and token
5. Set Hermes Telegram bot token and allowed users

6. Show Hermes configuration
7. Show container logs

8. Execute command inside container

0. Exit

───────────────────────────────────────────────────────────────────────────
```

### Options Breakdown

* **1. Install / Reinstall Hermes:** Pulls and unpacks the template, writes scoped container `.env` files, builds the Docker image, initializes `/data/hermes` persistence, and configures internal model routing (`openai-api` provider, default model `mimo-v2.5-free`). If already present, provides quick restart or rebuild options.


* **2. Install / Reconfigure 9Router:** Configures listening port (default: `20128`) and initial password (default: `123456`), pulls `ghcr.io/whoisneon/9router:latest`, attaches persistence to `${HOME}/hermes-manager/9router-data`, and spins up the container.


* **3. Install / Reconfigure FreeLLMAPI:** Configures listening port (default: `3001`), generates (once) and persists an `ENCRYPTION_KEY` for at-rest provider key storage, pulls `ghcr.io/tashfeenahmed/freellmapi:latest`, attaches persistence to `${HOME}/hermes-manager/freellmapi-data`, and spins up the container. On first run, open the dashboard and create the admin account — a one-time setup code is printed in the container logs (menu option `7`). Add your free provider keys on the Keys page and copy the unified API key to point Hermes or any OpenAI-compatible client at `.../v1`.


* **4. Set Hermes API endpoint and token:** Updates the target OpenAI-compatible endpoint and access token. Automatically updates container environment variables and internal `hermes config` values, restarting the container if running.


* **5. Set Hermes Telegram bot token and allowed users:** Configures Telegram bot credentials and numeric allowed user IDs, safely restarting the container to apply changes.


* **6. Show Hermes configuration:** Displays persisted configuration variables and runs `hermes config` inside the container while stripping sensitive keys and tokens from terminal output.


* **7. Show container logs:** Dumps the last 100 log lines for `hermes`, `9router`, or `freellmapi`.


* **8. Execute command inside container:** Drops into an interactive sub-shell execution loop inside either the `hermes`, `9router`, or `freellmapi` container (enter `exitnow` to return to the main menu).


* **0. Exit:** Cleanly closes the management console.



---

## Endpoint & Proxy Resolution

When 9Router is active, URLs resolve dynamically via local loopback and the resolved Daytona Sandbox identifier:

* **Local Dashboard:** `http://<CONTAINER_IP>:<PORT>`

* **Local API Base:** `http://<CONTAINER_IP>:<PORT>/v1`

* **Public Dashboard:** `https://<PORT>-<SANDBOX_ID>.proxy.daytona.work`

* **Public API Base:** `https://<PORT>-<SANDBOX_ID>.proxy.daytona.work/v1`


---

## Data Persistence & File Structure

The script organizes runtime configurations and storage across several host locations:

* **Hermes Storage (`/data/hermes`):** Mounted to `/data` inside the container. Preserves agent memory, skills, configurations, and conversation state across updates and container recreations.


* **9Router Storage (`${HOME}/hermes-manager/9router-data`):** Mounted to `/app/data` to retain router configuration and logs.


* **FreeLLMAPI Storage (`${HOME}/hermes-manager/freellmapi-data`):** Mounted to `/app/server/data` to retain the SQLite database (provider keys, models, settings — encrypted at rest) across container recreations.


* **CLI State (`${HOME}/hermes-manager/config.env`):** Saved with strict permissions (`0600`) to retain custom ports, passwords, the FreeLLMAPI encryption key, and model endpoint preferences across script sessions.



---

## Troubleshooting

* **Docker Daemon Issues:** `install.sh` automatically checks for Docker and attempts to spawn `dockerd` in the background if it is inactive. If connection issues persist, verify that your Daytona template is DinD-enabled (`ps aux | grep '[d]ockerd'`).


* **Telegram Bot Not Responding:** Ensure target user IDs in option `4` are numeric and comma-separated (e.g., `123456789,987654321`). You can view live output using option `6` in the menu or by running:


```bash
docker logs -f hermes
```


* **Interactive Container Debugging:** Use menu option `7` or manually access the environment:


```bash
docker exec -it hermes sh

```



---

## License

This project is licensed under the [`MIT License`](https://www.google.com/search?q=LICENSE).