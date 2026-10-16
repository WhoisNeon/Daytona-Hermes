# Hermes Agent & 9Router & FreeLLMAPI & Xray on Daytona

An interactive management console that deploys and operates **Hermes Agent**, **9Router**,
**FreeLLMAPI** and a dockerised **Xray** proxy core inside a Daytona Docker-in-Docker (DinD)
sandbox, with Telegram gateway integration.

---

## Overview

* **Daytona Sandbox:** Docker-in-Docker environment (`docker:29.4-dind`).
* **Hermes Agent:** Autonomous AI agent in an isolated container with local persistence.
* **Telegram Gateway:** Two-way messaging channel with user-ID whitelisting.
* **9Router:** OpenAI-compatible API gateway and dashboard ([official `decolua/9router`](https://hub.docker.com/r/decolua/9router) image).
* **FreeLLMAPI:** OpenAI-compatible gateway aggregating many free providers behind one `/v1` endpoint ([tashfeenahmed/freellmapi](https://github.com/tashfeenahmed/freellmapi)).
* **Xray Proxy:** Turns a `vless://`, `vmess://` or `trojan://` share link into a ready client config, with SOCKS (10808) and HTTP (10809) inbounds plus system-wide **and** Docker-wide proxying.
* **Management console:** A dependency-free, boxed TUI with a live status board, per-service submenus, masked secrets, one-command updates, safe uninstalls and automatic daemon recovery.

---

## Prerequisites

* A [Daytona Sandbox](https://app.daytona.io/dashboard/sandboxes) booted with a DinD image (e.g. `docker:29.4-dind`).
* Recommended: 2 vCPU, 4 GB RAM, 10 GB disk.
* Telegram Bot Token from [@BotFather](https://t.me/BotFather) and your numeric Telegram user ID.

---

## Install & Run

Bootstrap once inside your Daytona sandbox terminal:

```bash
wget -qO install.sh "https://raw.githubusercontent.com/WhoisNeon/Daytona-Hermes/main/install.sh?$(date +%s)" && sh install.sh
```

The console installs itself as a command on first run, so you can reopen it any time:

```bash
daytona-hermes
```

It copies the script to `~/hermes-manager/install.sh` and symlinks `daytona-hermes` into
`/usr/local/bin` (falling back to `~/.local/bin`). The symlink is refreshed automatically on
every launch, so a single `Update manager` always keeps the command current.

---

## The Console

On launch the console renders a status board followed by grouped menus:

```text
╭──────────────────────────────────────────────────────────────────────────╮
│ HERMES  -  Daytona Sandbox Edition                                       │
│ Hermes | 9Router | FreeLLMAPI | Xray            WhoisNeon | v0.3.0       │
│                                                                          │
│   Hermes        running                                                  │
│   9Router       running                                                  │
│   FreeLLMAPI    stopped                                                  │
│   Xray core     running                                                  │
│   System proxy  enabled                                                  │
│   Docker proxy  enabled                                                  │
╰──────────────────────────────────────────────────────────────────────────╯

  Setup
     1  Hermes                           install · rebuild · update
     2  9Router                          install · update · reconfigure
     3  FreeLLMAPI                       install · update · reconfigure
     4  Xray proxy                       node · system proxy · core

  Manage
     5  Hermes API endpoint & token
     6  Telegram bot & allowed users
     7  Hermes configuration
     8  Container logs
     9  Shell into a container
    10  Manager settings

     0  Exit

  Select [0-10]:
```

Every value starts at a colour-coded state (`running`, `stopped`, `not installed`,
`enabled`, `disabled`) so the whole stack is visible at a glance.

---

## Setup

### 1. Hermes

```text
  Status        running
  API           http://172.17.0.4:20128/v1
  Model         mimo-v2.5-free

     1  Install / Rebuild           download template, build image
     2  Update                      rebuild with the latest template
     3  Configure API endpoint & token
     4  Restart
     5  Stop
     6  Start
     7  Logs
     8  Shell
     9  Uninstall
     0  Back
```

* **Install / Rebuild** downloads the template, writes a scoped `.env`, builds the
  `hermes-agent:latest` image and starts the container.
* **Update** re-downloads the template and rebuilds the image without touching `/data`.
* Hermes is configured as a **custom OpenAI-compatible provider** (`model.provider custom` with
  `model.base_url` / `model.api_key`), so it can point at 9Router, FreeLLMAPI, OpenAI, Ollama or
  any compatible endpoint.
* **Uninstall** removes the container, then asks separately whether to delete `/data/hermes`,
  the image and the downloaded template (data is kept by default).

### 2. 9Router

```text
  Status        running
  Port          20128
  Local         http://172.17.0.4:20128

     1  Install / Reconfigure       port, password
     2  Update                      pull the latest image, keep data
     3  Restart
     4  Stop
     5  Start
     6  Logs
     7  Shell
     8  Uninstall
     0  Back
```

Runs the official **`decolua/9router:latest`** image with persistence at
`~/hermes-manager/9router-data` (`/app/data`). **Update** pulls the newest image and recreates
the container while keeping the data volume.

### 3. FreeLLMAPI

Same layout as 9Router. Generates and persists an `ENCRYPTION_KEY` for at-rest provider-key
storage, keeps data at `~/hermes-manager/freellmapi-data` (`/app/server/data`), and prints the
local and Daytona public URLs after install.

On first run, open the dashboard and create the admin account — a one-time setup code is printed
in the container logs (submenu → **Logs**). Then add provider keys and copy the unified API key
to point Hermes or any OpenAI-compatible client at `.../v1`.

### 4. Xray Proxy

```text
  Core          running
  System proxy  enabled
  Docker proxy  enabled
  Node          My Reality Node
  SOCKS / HTTP  socks5://127.0.0.1:10808 / http://127.0.0.1:10809

     1  Add / change node link
     2  Pause / resume system proxy      host shells + new containers
     3  Toggle Docker proxy              proxy for newly created containers
     4  Restart core
     5  Stop core
     6  Start core
     7  Update core image
     8  Test proxy latency
     9  Show logs
    10  Show client config
    11  Uninstall
     0  Back
```

* **Add / change node link** parses a `vless://`, `vmess://` (Base64 JSON) or `trojan://` link,
  shows a redacted summary, writes `config.json`, recreates the core and enables proxying.
  Transports: `tcp` (incl. `headerType=http`), `ws`, `grpc`, `httpupgrade`, `xhttp`, `kcp`.
  Security: `none`, `tls`, `reality`.
* **Pause / resume system proxy** toggles host proxying *and* the Docker client proxy together;
  the core keeps running so resuming is instant.
* **Test proxy latency** probes `google.com/generate_204` through `127.0.0.1:10809` and reports
  proxy latency, HTTP status, egress IP, and a direct baseline with the delta. It uses `curl`
  when present and falls back to the sandbox's busybox `wget`, so it works in minimal images.

---

## How Proxying Is Applied

The Xray core binds its inbounds to **`0.0.0.0`** so that clients on other interfaces can reach it:

* **Host tools** keep using loopback: `http://127.0.0.1:10809` / `socks5://127.0.0.1:10808`.
* **Containers** reach the same inbound through the Docker bridge gateway, e.g.
  `http://172.17.0.1:10809`.

This is written to three places so it applies immediately *and* survives:

1. **Current session** — exported into the running console process (and everything it spawns).
2. **`/etc/profile.d/hermes-xray-proxy.sh`** — picked up by every new login shell.
3. **`/etc/environment`** — picked up by PAM sessions. Stale proxy lines are filtered before
   rewriting, so repeated toggles never accumulate duplicates.

Because a child process cannot modify its parent's environment, apply it to your current shell
with:

```bash
. /etc/profile.d/hermes-xray-proxy.sh    # enable
rm /etc/profile.d/hermes-xray-proxy.sh   # disable (or just open a new terminal)
```

### Docker client proxy

For traffic *inside* other containers, the console merges a `proxies.default` block into
`~/.docker/config.json`. The Docker CLI then injects `http_proxy` / `https_proxy` / `no_proxy`
into **every container it creates**:

```json
{
  "proxies": {
    "default": {
      "httpProxy": "http://172.17.0.1:10809",
      "httpsProxy": "http://172.17.0.1:10809",
      "noProxy": "localhost,127.0.0.1,::1,0.0.0.0"
    }
  }
}
```

Notes:

* The gateway IP is resolved from the Docker bridge (falling back to `172.17.0.1`).
* An existing `config.json` is **merged** when `jq` or `python3` is available, and otherwise
  **backed up** to `~/.docker/config.json.hermes.bak` before being written fresh. Disabling the
  proxy restores the backup (or removes the file if it was created here).
* Docker only injects these variables at container **creation** time. To apply the proxy to an
  existing container, recreate it (every **Update** action does this).
* The toggle lives both in the Xray submenu (`3`) and in **Manager settings** (`3`).

> **Security:** the Xray inbounds are unauthenticated and bound to `0.0.0.0`. Anyone who can
> reach the sandbox's network can use the proxy. Only leave it enabled if that exposure is
> acceptable for your sandbox.

---

## Manage

| Option | Description |
| --- | --- |
| `5` Hermes API endpoint & token | Updates the custom OpenAI-compatible endpoint and token; rewrites `.env` and restarts the container. |
| `6` Telegram bot & allowed users | Sets the bot token and numeric allowed user IDs; applied on restart. |
| `7` Hermes configuration | Prints persisted config and `hermes config`, with secrets masked. |
| `8` Container logs | Last 100 lines for the selected component. |
| `9` Shell into a container | Interactive `bash` (or `sh`) inside the selected container. |
| `10` Manager settings | Console maintenance (below). |

### Manager settings

```text
     1  Update manager                 re-download install.sh
     2  Reinstall CLI command          write daytona-hermes to PATH
     3  Docker proxy (disabled)        proxy for new containers
     4  Show manager config
     5  Reset all data                 destructive
     0  Back
```

* **Update manager** re-downloads `install.sh` from the repository and refreshes the command.
* **Reset all data** removes every managed container, image and data directory after two
  confirmations.

---

## Endpoint & Proxy Resolution

When a gateway is running, URLs resolve to both a local and a public address:

* **Local dashboard:** `http://<CONTAINER_IP>:<PORT>`
* **Local API base:** `http://<CONTAINER_IP>:<PORT>/v1`
* **Public dashboard:** `https://<PORT>-<SANDBOX_ID>.proxy.daytona.work`
* **Public API base:** `https://<PORT>-<SANDBOX_ID>.proxy.daytona.work/v1`

---

## Data, Persistence & Updates

Updates are designed to preserve state:

* **Hermes update** re-pulls the template and rebuilds the image; `/data/hermes` is untouched.
* **9Router / FreeLLMAPI / Xray update** pull the newer image and recreate the container; the
  mounted data directory is untouched.
* **Uninstall** always asks before deleting data (default: keep).

| Path | Purpose |
| --- | --- |
| `/data/hermes` | Hermes agent memory, skills and state (mounted to `/data`). |
| `~/hermes-manager/9router-data` | 9Router data (`/app/data`). |
| `~/hermes-manager/freellmapi-data` | FreeLLMAPI database (`/app/server/data`, encrypted at rest). |
| `~/hermes-manager/xray-data/config.json` | Generated Xray client config (`0600`); bind-mounted read-only into the core. |
| `~/hermes-manager/xray-data/node.link` | The original share link (`0600`). |
| `~/hermes-manager/config.env` | Saved ports, passwords, encryption key, node label and endpoint prefs (`0600`). |
| `~/hermes-manager/install.sh` | The installed console, targeted by the `daytona-hermes` symlink. |
| `~/.docker/config.json` | Docker client proxy settings (backed up to `~/.docker/config.json.hermes.bak`). |

---

## Troubleshooting

* **Docker daemon issues:** the console checks for Docker and attempts to start `dockerd` if it
  is inactive. If problems persist, confirm your template is DinD-enabled
  (`ps aux | grep '[d]ockerd'`).
* **Telegram bot not responding:** make sure allowed user IDs are numeric and comma-separated
  (e.g. `123456789,987654321`), then follow the logs: `docker logs -f hermes`.
* **Proxy enabled but traffic broken:** the proxy points at the local Xray inbound. If the core
  is stopped while the proxy is on, proxied traffic fails. Pause the proxy (Xray submenu `2`) or
  start the core (`6`).
* **Containers still connect directly:** Docker's proxy is applied at container creation. Recreate
  the container (any **Update**) after enabling the Docker proxy.
* **`9Router` login differs from the old image:** the official image may not honour
  `INITIAL_PASSWORD`; check the container logs for the first-login credentials.
* **Node shows "not installed" or the latency test fails instantly:** inspect the generated
  config and core logs (Xray submenu `10` and `9`). A REALITY node missing `pbk`, or a link using
  the removed `h2`/`quic` transport, is rejected at parse time with a specific message.

---

## License

This project is licensed under the [`MIT License`](LICENSE).
