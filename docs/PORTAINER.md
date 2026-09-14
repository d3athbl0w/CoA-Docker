# 🚢 Portainer Deployment & Operator Guide — Conquest of Azeroth (CoA) Docker Repack

This comprehensive guide walks you through deploying the **AzerothCore WotLK / Conquest of Azeroth (CoA)** server repack on a remote server managed with **Portainer** (Community Edition or Business Edition). It covers the complete operational workflow from local image export to resolving common port, submodule, and database initialization hurdles.

---

## 📑 Table of Contents
1. [Remote Server Requirements](#1-remote-server-requirements)
2. [Architecture: Why Source Compilation Fails via Portainer Git](#2-architecture-why-source-compilation-fails-via-portainer-git)
3. [Step 1: Exporting Compiled Images from Your Local PC](#3-step-1-exporting-compiled-images-from-your-local-pc)
4. [Step 2: Importing Images into Portainer](#4-step-2-importing-images-into-portainer)
5. [Step 3: Creating and Deploying the Stack (Web Editor)](#5-step-3-creating-and-deploying-the-stack-web-editor)
6. [Step 4: Database Verification & Schema Provisioning](#6-step-4-database-verification--schema-provisioning)
7. [Step 5: Configuring Public WAN IP for Remote Players](#7-step-5-configuring-public-wan-ip-for-remote-players)
8. [Live Operations from the Portainer Web Interface](#8-live-operations-from-the-portainer-web-interface)
9. [Comprehensive Troubleshooting & FAQ](#9-comprehensive-troubleshooting--faq)

---

## 1. Remote Server Requirements

Before initiating deployment on the remote Portainer host, verify that the host machine satisfies the following hardware and networking prerequisites:

- **RAM Requirements:** Minimum 4 GB to 6 GB free memory (MySQL 8.4 + Worldserver indexing 5,744 maps, 12,494 collision vmaps, and 42,000+ custom appearances consume ~2.5 GB to 3 GB under normal load).
- **Storage:** At least 10 GB free disk space (for database persistence, logs, and game data assets).
- **Firewall Rules (Security Groups / UFW):**
  - `3724 TCP`: Authserver (Authentication, SRP6 proofs, realm selection).
  - `8085 TCP`: Worldserver (Active game world connection).
  - `3306 TCP`: *(Optional)* MySQL database (only if connecting external tools like HeidiSQL or DBeaver from your workstation).
  - `3443 TCP`: *(Optional)* Remote Access (RA) CLI console.

---

## 2. Architecture: Why Source Compilation Fails via Portainer Git

If you attempt to use Portainer's **Build method: Repository** pointing directly to the Git repository, **the deployment will fail** due to two architectural constraints:

1. **Non-Recursive Git Submodules:** The AzerothCore C++ source tree resides under `source/` as a Git submodule. Portainer's default Git engine runs a shallow `git clone` without `--recurse-submodules`, leaving the `source/` directory empty. When Docker BuildKit triggers the build, it halts with:  
   `failed to compute cache key: "/source/modules": not found`.
2. **Resource Exhaustion (OOM Killer):** Compiling AzerothCore C++ from source requires 30 to 50 minutes of high CPU utilization and up to 6 GB of RAM during the linking phase (`clang`/`ld`). On modest VPS instances, the Linux kernel terminates the compiler process (*Exit Code 137 / Out of Memory*).

> [!TIP]
> **DevOps Best Practice:**  
> The images are already compiled on your development workstation. Exporting these compiled containers, importing them into Portainer, and allowing the automated `ac-data-init` container to provision the 1.15 GB game assets directly on the host completes the entire deployment in **under 30 seconds**.

---

## 3. Step 1: Exporting Compiled Images from Your Local PC

To prevent binary pipeline corruption caused by Windows terminal streams (PowerShell / CMD text encoding), **do not use shell pipes (`| gzip`)**. Always use Docker's native file output flag (`-o`):

Open PowerShell or Git Bash on your local PC and execute:

```powershell
docker save -o coa-server-images.tar coa/ac-authserver:latest coa/ac-worldserver:latest coa/ac-db-import:latest
```

This packages all three compiled images directly into a single, clean `coa-server-images.tar` archive (~1.5 GB to 2.0 GB uncompressed).

---

## 4. Step 2: Importing Images into Portainer

1. Log into your **Portainer** dashboard.
2. Select your environment (typically named `local` or `primary`).
3. In the left navigation sidebar, click on **Images**.
4. **Attention to UI Details:**
   - ❌ **DO NOT CLICK:** `+ Build a new image` (this expects source code with a `Dockerfile` and will fail with `Cannot locate specified Dockerfile: Dockerfile`).
   - ✅ **CLICK ON:** **`Import image`** (located on the top action bar next to Build).
5. On the **Import image** screen:
   - Click **Select file** and choose `coa-server-images.tar` from your local machine.
   - Click the blue **Upload** button.
6. Wait for the upload to complete. You will see a green success notification, and the three images will be listed in the image table:
   - `coa/ac-authserver:latest`
   - `coa/ac-worldserver:latest`
   - `coa/ac-db-import:latest`

---

## 5. Step 3: Creating and Deploying the Stack (Web Editor)

1. In the left navigation sidebar, click on **Stacks**.
2. Click on the **`+ Add stack`** button.
3. **Name:** Enter `coa-repack`.
4. **Build method:** Select the **Web editor** tab (first option).
5. In the web editor text area, paste the following standalone production stack definition:

```yaml
services:
  ac-database:
    container_name: ac-database
    image: mysql:8.4
    networks:
      - ac-network
    ports:
      - "3306:3306"
    environment:
      MYSQL_ROOT_PASSWORD: password
    volumes:
      - ac-database-data:/var/lib/mysql
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "/usr/bin/mysqladmin ping -h localhost -u root -ppassword"]
      interval: 5s
      timeout: 10s
      retries: 30
      start_period: 15s

  ac-data-init:
    container_name: ac-data-init
    image: alpine:3.20
    restart: "no"
    networks:
      - ac-network
    volumes:
      - ac-client-data:/azerothcore/env/dist/data
    environment:
      DATA_URL: "https://github.com/d3athbl0w/CoA-Docker/releases/download/master/Data.zip"
      EXPECTED_SHA256: "92ba82ebc19ba820e004e8d4d4b89ee7c415d9e4124d92f29312f0e049c61079"
    command:
      - sh
      - -c
      - |
        set -eu
        TARGET_DIR="/azerothcore/env/dist/data"
        if [ -f "$$TARGET_DIR/dbc/AreaTable.dbc" ] && [ -f "$$TARGET_DIR/dbc/Ascension/Appearances.dbc" ]; then
          echo "[ac-data-init] Game data already present. Skipping download."
          exit 0
        fi

        echo "[ac-data-init] Game data missing. Installing utilities..."
        apk add --no-cache curl unzip ca-certificates

        mkdir -p "$$TARGET_DIR" /tmp/coa-downloads
        ARCHIVE="/tmp/coa-downloads/Data.zip"

        echo "[ac-data-init] Downloading CoA Game Data (~466 MB)..."
        curl -L -f --progress-bar -o "$$ARCHIVE" "$$DATA_URL"

        echo "[ac-data-init] Verifying SHA-256 checksum..."
        echo "$$EXPECTED_SHA256  $$ARCHIVE" | sha256sum -c -

        echo "[ac-data-init] Extracting game data into $$TARGET_DIR..."
        unzip -o -q "$$ARCHIVE" -d "$$TARGET_DIR"
        rm -rf /tmp/coa-downloads

        echo "[ac-data-init] Game data bootstrap completed successfully."

  ac-db-import:
    container_name: ac-db-import
    image: coa/ac-db-import:latest
    networks:
      - ac-network
    environment:
      AC_DATA_DIR: "/azerothcore/env/dist/data"
      AC_LOGS_DIR: "/azerothcore/env/dist/logs"
      AC_LOGIN_DATABASE_INFO: "ac-database;3306;root;password;acore_auth"
      AC_WORLD_DATABASE_INFO: "ac-database;3306;root;password;acore_world"
      AC_CHARACTER_DATABASE_INFO: "ac-database;3306;root;password;acore_characters"
    volumes:
      - ac-server-etc:/azerothcore/env/dist/etc
      - ac-server-logs:/azerothcore/env/dist/logs
    depends_on:
      ac-database:
        condition: service_healthy

  ac-authserver:
    container_name: ac-authserver
    image: coa/ac-authserver:latest
    networks:
      - ac-network
    ports:
      - "3724:3724"
    environment:
      AC_LOGS_DIR: "/azerothcore/env/dist/logs"
      AC_TEMP_DIR: "/azerothcore/env/dist/temp"
      AC_LOGIN_DATABASE_INFO: "ac-database;3306;root;password;acore_auth"
    volumes:
      - ac-server-etc:/azerothcore/env/dist/etc
      - ac-server-logs:/azerothcore/env/dist/logs
    restart: unless-stopped
    depends_on:
      ac-database:
        condition: service_healthy
      ac-db-import:
        condition: service_completed_successfully

  ac-worldserver:
    container_name: ac-worldserver
    image: coa/ac-worldserver:latest
    networks:
      - ac-network
    stdin_open: true
    tty: true
    ports:
      - "8085:8085"
      - "3443:3443"
    environment:
      AC_DATA_DIR: "/azerothcore/env/dist/data"
      AC_LOGS_DIR: "/azerothcore/env/dist/logs"
      AC_LOGIN_DATABASE_INFO: "ac-database;3306;root;password;acore_auth"
      AC_WORLD_DATABASE_INFO: "ac-database;3306;root;password;acore_world"
      AC_CHARACTER_DATABASE_INFO: "ac-database;3306;root;password;acore_characters"
      AC_ASCENSION_COMPAT_DBC_DIRECTORY: "/azerothcore/env/dist/data/dbc/Ascension"
    volumes:
      - ac-server-etc:/azerothcore/env/dist/etc
      - ac-server-logs:/azerothcore/env/dist/logs
      - ac-client-data:/azerothcore/env/dist/data:ro
    restart: unless-stopped
    depends_on:
      ac-database:
        condition: service_healthy
      ac-db-import:
        condition: service_completed_successfully
      ac-data-init:
        condition: service_completed_successfully

volumes:
  ac-database-data:
  ac-server-etc:
  ac-server-logs:
  ac-client-data:

networks:
  ac-network:
    name: ac-network
    driver: bridge
```

6. Scroll to the bottom of the page and click **`Deploy the stack`**.

---

## 6. Step 4: Database Verification & Schema Provisioning

Upon deployment, Portainer automatically orchestrates startup order:
1. `ac-database` starts first and transitions to **Healthy** state.
2. `ac-data-init` downloads `Data.zip` (~466 MB), verifies SHA-256 integrity, extracts all assets into `ac-client-data`, and shuts down with code **`Exited (0)`** (expected behavior).
3. `ac-db-import` connects to MySQL, initializes base schemas, and shuts down with **`Exited (0)`** (expected behavior).
4. `ac-authserver` and `ac-worldserver` start up.

### What if `acore_auth`, `acore_characters`, and `acore_world` are missing?
If MySQL initialized as a bare/empty instance without the three game schemas:

1. In Portainer, navigate to **Containers** and click on **`ac-database`**.
2. Click the **Console** button (terminal icon `>_`) ➔ select `/bin/sh` ➔ click **Connect**.
3. Launch the MySQL CLI client:
   ```bash
   mysql -u root -ppassword
   ```
4. Execute the schema initialization SQL:
   ```sql
   CREATE DATABASE IF NOT EXISTS acore_auth DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   CREATE DATABASE IF NOT EXISTS acore_characters DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   CREATE DATABASE IF NOT EXISTS acore_world DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

   CREATE USER IF NOT EXISTS 'acore'@'%' IDENTIFIED BY 'password';
   GRANT ALL PRIVILEGES ON *.* TO 'acore'@'%' WITH GRANT OPTION;
   FLUSH PRIVILEGES;

   SHOW DATABASES;
   ```
5. Type `exit`, close the terminal, and restart **`ac-authserver`** and **`ac-worldserver`** in Portainer using the **Restart** button.

---

## 7. Step 5: Configuring Public WAN IP for Remote Players

By default, AzerothCore registers the realm address as `127.0.0.1`. For external players connecting across the internet:

1. Open the interactive console on `ac-database` (as described in Step 4).
2. Connect to MySQL: `mysql -u root -ppassword`
3. Update the realm table with your remote server's public IP address or FQDN:
   ```sql
   UPDATE acore_auth.realmlist SET address = 'YOUR_PUBLIC_IP_OR_DOMAIN' WHERE id = 1;
   SELECT id, name, address, port FROM acore_auth.realmlist;
   ```
4. Remote players must configure their game client's `realmlist.wtf` file accordingly:
   ```text
   set realmlist YOUR_PUBLIC_IP_OR_DOMAIN
   ```

---

## 8. Live Operations from the Portainer Web Interface

### 📄 Inspecting Real-Time Logs
- In **Containers**, click the document icon (Logs) next to `ac-worldserver`.
- Toggle on **Auto-refresh**.
- You will see the complete initialization sequence:
  ```text
  Loading Ascension collection data: 42884 appearances, 202913 item mappings...
  Ascension compatibility enabled; consuming extension opcodes 0x051F-0x09D3...
  WORLD: World Initialized In 0 Minutes 26 Seconds
  AC>
  ```

### 💻 Interacting with the World Console (`AC>`)
- In **Containers**, click the terminal icon `>_` (Console) next to `ac-worldserver`.
- Select **Attach** and click **Connect**.
- You will be connected directly to the interactive `AC>` world prompt inside your browser. Run Game Master commands (e.g. `.server info`, `.account create <name> <pass>`, `.announce`).

---

## 9. Comprehensive Troubleshooting & FAQ

### Error 1: `archive/tar: invalid tar header`
- **Root Cause:** The image archive was exported in Windows using pipeline redirection (`| gzip`), altering POSIX null byte padding and corrupting the tar header.
- **Solution:** Always export using Docker's native `-o` flag:  
  `docker save -o coa-server-images.tar coa/ac-authserver:latest ...`

### Error 2: `Cannot locate specified Dockerfile: Dockerfile`
- **Root Cause:** The `.tar` image archive was uploaded under **`+ Build a new image`**. That screen compiles source code and expects a text `Dockerfile`.
- **Solution:** Navigate to **Images** ➔ click **`Import image`** (NOT *Build*).

### Error 3: `Bind for 0.0.0.0:7878 failed: port is already allocated`
- **Root Cause:** Host port `7878` (default SOAP management port) is already bound by another service on the server (e.g., Radarr or another game emulator).
- **Solution:** Players do not connect through SOAP. Remove the `- "7878:7878"` port binding from `ac-worldserver` in Compose. Only ports `3724` and `8085` are required.

### Error 4: `Failed to find map files for starting areas`
- **Root Cause:** `ac-worldserver` attempted to start with an unpopulated `./data` directory.
- **Solution:** The included `ac-data-init` container prevents this by automatically downloading, verifying (SHA-256), and extracting `Data.zip` before `ac-worldserver` starts.

### Error 5: Missing Game Content (Empty World / No CoA Quests or Custom Classes)
- **Root Cause:** MySQL initialized empty schemas without the Conquest of Azeroth content database.
- **Solution:** In Phase 3B, restore the official CoA clean snapshot (`Database/Clean/databases.sql.gz`), which populates all custom classes (IDs 12–32), custom appearances, quest templates, and default GM account credentials (`local` / `local`).
