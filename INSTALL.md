# Installation & Operator Guide: AzerothCore WotLK (CoA) Docker Repack

This guide walks you through setting up and running the AzerothCore Conquest of Azeroth Docker repack from scratch. It is written for all skill levels, including users who have never used Docker before.

---

## 📑 Table of Contents
1. [Prerequisites](#1-prerequisites)
2. [Cloning the Repository](#2-cloning-the-repository)
3. [Environment Configuration](#3-environment-configuration)
4. [Downloading & Installing Game Data](#4-downloading--installing-game-data)
5. [Building the Docker Images](#5-building-the-docker-images)
6. [Starting the Servers](#6-starting-the-servers)
7. [Monitoring & Verification](#7-monitoring--verification)
8. [Interacting with the World Console](#8-interacting-with-the-world-console)
9. [Stopping & Restarting](#9-stopping--restarting)
10. [Rebuilding After Code Changes](#10-rebuilding-after-code-changes)
11. [Container Teardown vs. Volume Removal](#11-container-teardown-vs-volume-removal)
12. [Troubleshooting & FAQ](#12-troubleshooting--faq)

---

## 1. Prerequisites

Before starting, install the required software for your operating system:

### Windows 10/11
1. Download and install **[Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/)**.
2. During installation, select **Use WSL 2 instead of Hyper-V (recommended)**.
3. Install **[Git for Windows](https://git-scm.com/download/win)**.
4. Launch Docker Desktop and verify the whale icon in your system tray shows "Engine running".
5. Open PowerShell or Windows Terminal and test:
   ```powershell
   docker --version
   docker compose version
   git --version
   ```

### Linux (Ubuntu / Debian)
1. Install Docker Engine and Compose plugin via the official Docker repository:
   ```bash
   sudo apt-get update
   sudo apt-get install -y ca-certificates curl gnupg
   sudo install -m 0755 -d /etc/apt/keyrings
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
   sudo chmod a+r /etc/apt/keyrings/docker.gpg
   echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
   sudo apt-get update
   sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
   ```
2. Enable non-root Docker usage:
   ```bash
   sudo usermod -aG docker $USER
   newgrp docker
   ```

### macOS (Apple Silicon / Intel)
1. Download and install **[Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/)**.
2. Start Docker Desktop and verify `docker` and `docker compose` in Terminal.

---

## 2. Cloning the Repository

This repack incorporates the AzerothCore source tree as a Git submodule. Always clone with `--recurse-submodules`:

```bash
git clone --recurse-submodules https://github.com/d3athbl0w/CoA-Docker.git CoA-Docker
cd CoA-Docker
```

> [!TIP]
> **Forgot `--recurse-submodules`?**  
> If you cloned without this flag and the `source/` folder is empty, simply initialize the submodule manually:
> ```bash
> git submodule update --init --recursive
> ```

---

## 3. Environment Configuration

The environment configuration file stores passwords, port mappings, user IDs, and container settings.

1. Create your local `.env` file by copying the template:
   ```bash
   cp .env.example .env
   ```
   *(On Windows Command Prompt or PowerShell: `copy .env.example .env`)*

2. Open `.env` in any text editor. Review the default values:
   - `DOCKER_DB_ROOT_PASSWORD`: The root password for MySQL (default: `password`). Change this for production use!
   - `DOCKER_DB_EXTERNAL_PORT`: Port exposed on host for database tools (default: `3306`).
   - `DOCKER_AUTH_EXTERNAL_PORT`: Port for WoW client authentication (default: `3724`).
   - `DOCKER_WORLD_EXTERNAL_PORT`: Port for WoW realm connections (default: `8085`).

---

## 4. Downloading & Installing Game Data

AzerothCore requires extracted client DBCs, terrain maps, collision vmaps, and cameras to run. The official Conquest of Azeroth dataset is bundled in `Data.zip`.

### Automated Setup (Recommended)
Run the automated repack setup script, which initializes the submodules, downloads `Data.zip`, verifies the SHA256 checksum, and validates all extracted files:

```bash
# On Linux / macOS:
./scripts/repack.sh setup

# On Windows (PowerShell):
.\scripts\repack.ps1 setup
```

### Manual Download & Verification
If you prefer step-by-step control:
```bash
# Linux / macOS:
./scripts/download-data.sh
./scripts/validate-data.sh

# Windows (PowerShell):
.\scripts\download-data.ps1
.\scripts\validate-data.ps1
```

Validation will confirm that all directories (`data/dbc`, `data/dbc/Ascension`, `data/maps`, `data/vmaps`, `data/Cameras`) are present with over 18,500 total game assets.

---

## 5. Building the Docker Images

Compile AzerothCore and create your container images:

```bash
# Linux / macOS:
./scripts/repack.sh build

# Windows (PowerShell):
.\scripts\repack.ps1 build

# Or directly via Docker Compose:
docker compose build
```

### What happens during this step?
- Docker invokes BuildKit and starts the multi-stage compiler container.
- It pulls Ubuntu 24.04 and installs the Clang 18 toolchain, Boost, MySQL development packages, CMake, and Ninja.
- Ninja compiles `authserver`, `worldserver`, `dbimport`, and extractor tools in parallel.
- Stripped binaries and configuration templates are extracted into minimal runtime images.
- Compilation output is cached with BuildKit's compiler cache, ensuring future rebuilds only compile altered source files.

> [!NOTE]
> Compilation typically takes between 5 and 20 minutes depending on your CPU core count.

---

## 6. Starting the Servers

Once the build finishes, start the complete stack in detached (background) mode:

```bash
docker compose up -d
```

### Execution Sequence:
1. `ac-database` starts first and runs MySQL 8.4 LTS initialization.
2. The healthcheck periodically tests MySQL until it is accepting queries.
3. `ac-db-import` triggers automatically once the database is healthy. It creates missing databases (`acore_auth`, `acore_characters`, `acore_world`) and applies base tables and schema updates.
4. Once `ac-db-import` completes successfully, `ac-authserver` and `ac-worldserver` start automatically.

---

## 7. Monitoring & Verification

### Checking Container Status
Check whether all services are running:
```bash
docker compose ps
```
You should see:
- `ac-database`: Up (healthy)
- `ac-db-import`: Exited (0) *(Success! It ran its migrations and terminated cleanly)*
- `ac-authserver`: Up
- `ac-worldserver`: Up

### Reading Server Logs
Follow live logs from all containers:
```bash
docker compose logs -f
```

To view logs for a specific service:
```bash
# View Auth Server logs:
docker compose logs -f ac-authserver

# View World Server logs:
docker compose logs -f ac-worldserver

# View Database logs:
docker compose logs -f ac-database
```

To exit log following, press `CTRL + C`.

---

## 8. Interacting with the World Console

The World Server features an interactive in-game administration console (for running commands like `server info`, `account create`, etc.).

To attach to the world server console:
```bash
docker attach ac-worldserver
```
Or run the helper script:
```bash
./scripts/console.sh
```

> [!IMPORTANT]
> **How to Detach Without Stopping the Server:**  
> If you press `CTRL + C` while attached, it will send SIGINT and **terminate** the worldserver!  
> To detach safely and leave the server running in the background, use the Docker detach escape key sequence:  
> **Press `CTRL + P` followed immediately by `CTRL + Q`**.

---

## 9. Stopping & Restarting

### Stopping the Servers
To pause or shut down the containers gracefully:
```bash
docker compose stop
```
Or to stop and remove disposable container layers:
```bash
docker compose down
```
*(Your characters, accounts, and database remain 100% safe on named volumes).*

### Restarting the Servers
```bash
docker compose restart
```

---

## 10. Rebuilding After Code Changes

If you pull new commits into `source/` or modify C++ files:
```bash
# Rebuild worldserver specifically
docker compose build ac-worldserver

# Recreate and start the updated container
docker compose up -d --no-deps ac-worldserver
```

Because BuildKit caches object files in a persistent compiler cache volume, subsequent builds typically complete in under 60 seconds.

---

## 11. Container Teardown vs. Volume Removal

It is essential to understand the difference between stopping containers and wiping volumes:

### Safe Teardown (Preserves All Data)
```bash
docker compose down
```
- Stops and removes container processes and internal networks.
- **Keeps all database tables, user accounts, and world state** stored in Docker named volumes (`ac-database-data`).

---

### Destructive Teardown (Destroys Database Data)
```bash
docker compose down -v
```
> [!CAUTION]
> The `-v` flag stands for **volumes**.  
> Executing `docker compose down -v` permanently deletes the `ac-database-data` volume!  
> All accounts, characters, and custom data will be irreversibly erased. Never run this command unless you intend to perform a total factory reset of your database.

---

## 12. Troubleshooting & FAQ

### Q: `ac-worldserver` logs say `Unable to open dbc/...` or `Failed to find map files`.
**Cause:** Game data has not been extracted into the `data/` directory.  
**Solution:** Run `./scripts/repack.sh download-data` (Linux/macOS) or `.\scripts\repack.ps1 download-data` (Windows) to automatically fetch and unpack the verified dataset. Run `validate-data` to confirm.

### Q: `docker compose up` fails with `port 3306 already in use`.
**Cause:** A local MySQL or MariaDB instance is already running on your host machine on port 3306.  
**Solution:** Edit `.env` and change `DOCKER_DB_EXTERNAL_PORT=3307`, then re-run `docker compose up -d`.

### Q: How do I connect to MySQL using HeidiSQL or DBeaver?
- **Host:** `127.0.0.1` (or `localhost`)
- **Port:** `3306` (or whatever you configured in `DOCKER_DB_EXTERNAL_PORT`)
- **User:** `root`
- **Password:** The password configured in `DOCKER_DB_ROOT_PASSWORD` in your `.env` (default: `password`).
