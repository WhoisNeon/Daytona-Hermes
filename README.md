# Hermes Agent & 9Router on Daytona

A management toolkit and deployment pipeline for running Hermes Agent and 9Router inside a Daytona Docker-in-Docker (DinD) sandbox with Telegram gateway integration.

---

## Architecture Overview

* **Daytona Sandbox:** Containerized DinD environment (`docker:*-dind`).
* **Hermes Agent:** Autonomous AI agent operating inside an isolated container.
* **Telegram Gateway:** Direct two-way messaging channel for authorized users.
* **9Router:** OpenAI-compatible API gateway serving custom language models.
* **install.sh:** Interactive TUI manager handling validation, secret masking, and dynamic Daytona proxy URL routing.

---

## Prerequisites

* A **[Daytona Sandbox](https://app.daytona.io/dashboard/sandboxes)** booted with a Docker-in-Docker image (e.g., `docker:29.4-dind`).
* Minimum specs: 2 vCPU, 4 GB RAM, 10 GB disk.
* A Telegram Bot Token from [@BotFather](https://t.me/BotFather).
* Your numerical Telegram User ID.

---

## Quick Start

Launch the interactive console directly inside your Daytona terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/WhoisNeon/Daytona-Hermes/main/install.sh | bash
```