# Hermes Agent & 9Router & FreeLLMAPI & Xray on Daytona

An interactive management CLI and deployment toolkit for orchestrating Hermes Agent, 9Router, FreeLLMAPI and an Xray proxy core inside a Daytona Docker-in-Docker (DinD) sandbox with Telegram gateway integration.

---

## Overview

* **Daytona Sandbox:** Docker-in-Docker environment (`docker:29.4-dind`).
* **Hermes Agent:** Autonomous AI agent operating in an isolated container with local persistence.
* **Telegram Gateway:** Direct two-way messaging channel with user ID whitelisting.
* **9Router:** Local/public OpenAI-compatible API gateway and management dashboard.
* **FreeLLMAPI:** Local/public OpenAI-compatible gateway aggregating 34+ free LLM providers (635+ model endpoints) behind one `/v1` endpoint with smart routing and automatic failover ([tashfeenahmed/freellmapi](https://github.com/tashfeenahmed/freellmapi)).
* **Xray Proxy:** Dockerised Xray core that turns a `vless://`, `vmess://` or `trojan://` share link into a ready-to-use client config, with SOCKS (10808) and HTTP (10809) local inbounds plus a system-wide proxy toggle.
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

  Xray core:                 Running
  Xray system proxy:         Enabled
  Xray node:                 My Reality Node
  Xray SOCKS / HTTP:         socks5://127.0.0.1:10808 / http://127.0.0.1:10809

───────────────────────────────────────────────────────────────────────────

1. Install / Reinstall Hermes
2. Install / Reconfigure 9Router
3. Install / Reconfigure FreeLLMAPI

4. Set Hermes API endpoint and token
5. Set Hermes Telegram bot token and allowed users

6. Show Hermes configuration
7. Show container logs

8. Execute command inside container

9. Xray proxy (node / system proxy / core / latency)

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


* **9. Xray proxy:** Opens the v2rayN-style proxy submenu described in [Xray Proxy](#xray-proxy).


* **0. Exit:** Cleanly closes the management console.



---

## Xray Proxy

Menu option `9` turns the sandbox into a proxy client. Paste a share link once and the
script writes a standard Xray `config.json`, runs the core in Docker and wires up the
system proxy.

```text
--- Xray Proxy ---

  Core:          Running
  System proxy:  Enabled
  Node:          My Reality Node
  SOCKS:         socks5://127.0.0.1:10808
  HTTP:          http://127.0.0.1:10809

1. Add / Change node link
2. Pause / Resume system proxy

3. Restart core
4. Stop core
5. Start core

6. Test proxy latency
7. Show Xray logs
8. Show Xray client config

0. Back
```

### Submenu Options

* **1. Add / Change node link:** Prompts for a `vless://`, `vmess://` (Base64 JSON) or
  `trojan://` share link, percent-decodes every parameter, shows a redacted summary for
  confirmation, then writes `config.json`, recreates the container and enables the proxy.
  Supported transports: `tcp` (including `headerType=http` obfuscation), `ws`, `grpc`,
  `httpupgrade`, `xhttp` and `kcp`; supported security: `none`, `tls` and `reality`.
* **2. Pause / Resume system proxy:** Toggles the environment variables only — the core
  keeps running, so resuming is instant. Handy when you need direct connectivity
  temporarily.
* **3. / 4. / 5. Restart, Stop, Start core:** Container lifecycle control for the `xray`
  container.
* **6. Test proxy latency:** `curl` through `127.0.0.1:10809` to `google.com/generate_204`,
  reporting total time in milliseconds, the HTTP status, the egress IP, and a direct
  (no-proxy) baseline with the delta.
* **7. / 8. Show logs / Show config:** Dumps the last 100 container log lines, or prints
  the generated `config.json`.

### How the Proxy Is Applied

The variables are written in three places so they apply immediately *and* survive:

* **Current session** — exported directly into the running `install.sh` process (and thus
  into every command it spawns, such as `wget` and `curl`).
* **`/etc/profile.d/hermes-xray-proxy.sh`** — picked up by every new login shell.
* **`/etc/environment`** — picked up by PAM sessions. Existing proxy lines are filtered
  out before rewriting so repeated toggles never leave stale duplicates behind.

Because a child process cannot modify its parent's environment, apply the change to the
terminal you are already sitting in with:

```bash
. /etc/profile.d/hermes-xray-proxy.sh    # enable
rm /etc/profile.d/hermes-xray-proxy.sh   # disable (or open a new terminal)
```

Writing to `/etc` requires root. Without it the toggle still works for the current
script session and the script prints a warning.

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


* **Xray Config (`${HOME}/hermes-manager/xray-data/config.json`):** The generated Xray client configuration, bind-mounted read-only into the `xray` container at `/etc/xray/config.json`. Saved with strict permissions (`0600`) since it contains the node UUID/password.


* **Xray Node Link (`${HOME}/hermes-manager/xray-data/node.link`):** The original share link, kept verbatim at `0600` so the exact node can be restored or re-applied later.


* **Xray Proxy Script (`/etc/profile.d/hermes-xray-proxy.sh`):** Generated on demand when the system proxy is enabled and deleted again when it is paused. Its presence is what the dashboard reads to report `Enabled` vs `Disabled`.


* **CLI State (`${HOME}/hermes-manager/config.env`):** Saved with strict permissions (`0600`) to retain custom ports, passwords, the FreeLLMAPI encryption key, the Xray node label, and model endpoint preferences across script sessions.



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



* **Proxy Enabled but Traffic Is Broken:** The system proxy points at `127.0.0.1:10809` on the sandbox. If the core is stopped while the proxy is on, all proxied traffic fails. Use submenu option `2` to pause, or `5` to start the core.


* **Node Shows "Not installed" or Curl Fails Immediately:** Inspect the generated file and the core logs with submenu options `8` and `7`. A REALITY node without its `pbk` parameter, or a link using the removed `h2`/`quic` transport, is rejected at parse time with a specific message.


---

## License

This project is licensed under the [`MIT License`](https://www.google.com/search?q=LICENSE).