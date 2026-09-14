# 🔄 Maintenance & Update Guide: AzerothCore WotLK (CoA) Docker & Portainer

This guide outlines standard operating procedures for updating, maintaining, and backing up the **AzerothCore Conquest of Azeroth (CoA)** Docker repack. It provides step-by-step instructions for both local Docker CLI environments and remote **Portainer** server installations.

---

## 📑 Table of Contents
1. [Core Principles: Stateless Containers vs. Persistent Volumes](#1-core-principles-stateless-containers-vs-persistent-volumes)
2. [Mandatory Pre-Update Routine: Database Backup](#2-mandatory-pre-update-routine-database-backup)
3. [Updating Server Binaries & Core Images](#3-updating-server-binaries--core-images)
   - [Workflow A: Local Docker Compose Update](#workflow-a-local-docker-compose-update)
   - [Workflow B: Remote Portainer Update](#workflow-b-remote-portainer-update)
4. [Applying Database Schema Migrations & SQL Updates](#4-applying-database-schema-migrations--sql-updates)
5. [Updating Server Configuration Files (`config/`)](#5-updating-server-configuration-files-config)
6. [Updating Game Data Assets (`ac-data-init`)](#6-updating-game-data-assets-ac-data-init)
7. [Updating Portainer CE on the Remote Server](#7-updating-portainer-ce-on-the-remote-server)
8. [Updating Docker Engine on the Host OS](#8-updating-docker-engine-on-the-host-os)
9. [Disaster Recovery & Rollback Procedures](#9-disaster-recovery--rollback-procedures)
10. [Routine Maintenance Checklist](#10-routine-maintenance-checklist)

---

## 1. Core Principles: Stateless Containers vs. Persistent Volumes

In this architecture, server components are strictly decoupled into two distinct operational layers:

| Layer | Components | Update Behavior |
|---|---|---|
| **Stateless Layer** | `ac-authserver`, `ac-worldserver`, `ac-db-import`, `ac-data-init` | Can be stopped, destroyed, rebuilt, and re-created at any time without data loss. |
| **Stateful Layer** | `ac-database-data`, `ac-server-etc`, `ac-client-data`, `ac-server-logs` | Persistent Docker volumes containing accounts, characters, guild state, world changes, and configuration. |

> [!CAUTION]
> **The Golden Rule of Updates:**  
> Never run `docker compose down -v` or delete Docker volumes in Portainer during maintenance. Volume removal permanently destroys your game world, character progression, and accounts.

---

## 2. Mandatory Pre-Update Routine: Database Backup

Always create a complete logical dump of the three game databases (`acore_auth`, `acore_characters`, `acore_world`) before applying core updates, compiling new C++ code, or running migrations.

### Method 1: Backup via Local Terminal (PowerShell or Bash)

Run this command from your host terminal to export a timestamped SQL dump directly from the running `ac-database` container:

#### Windows PowerShell:
```powershell
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
docker exec ac-database /usr/bin/mysqldump -u root -ppassword --databases acore_auth acore_characters acore_world | Set-Content -Encoding UTF8 "backup_coa_$timestamp.sql"
```

#### Linux / macOS Bash:
```bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
docker exec ac-database /usr/bin/mysqldump -u root -ppassword --databases acore_auth acore_characters acore_world | gzip > "backup_coa_${TIMESTAMP}.sql.gz"
```

### Method 2: Backup via Portainer Web Interface

If managing a remote server without external MySQL port exposure:

1. In Portainer, navigate to **Containers** ➔ Click on **`ac-database`**.
2. Click **Console** (terminal icon `>_`) ➔ Select `/bin/sh` ➔ Click **Connect**.
3. Run `mysqldump` to a file inside the container:
   ```bash
   mysqldump -u root -ppassword --databases acore_auth acore_characters acore_world > /var/lib/mysql/pre_update_backup.sql
   ```
4. This backup file resides safely inside the persistent volume `ac-database-data` under `/var/lib/mysql/`.

---

## 3. Updating Server Binaries & Core Images

When upstream AzerothCore commits, bug fixes, or custom C++ module changes are made in the source repository:

### Workflow A: Local Docker Compose Update

1. **Pull the latest code and recursive submodules:**
   ```bash
   git pull origin master
   git submodule update --init --recursive
   ```

2. **Recompile the images:**
   Docker BuildKit caches unchanged layers and only rebuilds modified C++ translation units:
   ```bash
   docker compose build
   ```

3. **Restart the containers with the newly built images:**
   ```bash
   docker compose up -d
   ```

4. **Verify startup logs:**
   ```bash
   docker compose logs -f ac-worldserver
   ```

---

### Workflow B: Remote Portainer Update

Remote servers running Portainer cannot compile the C++ source code reliably due to submodule cloning limitations and memory constraints (OOM killer). Always follow this build-and-transfer pipeline:

#### Step 1: Compile & Export on Your Local PC
On your local development machine:

```powershell
# 1. Update source code
git pull origin master
git submodule update --init --recursive

# 2. Build updated images
docker compose build

# 3. Export images to an archive using the native -o flag (prevents tar header corruption)
docker save -o coa-server-images-update.tar coa/ac-authserver:latest coa/ac-worldserver:latest coa/ac-db-import:latest
```

#### Step 2: Import the Updated Images into Portainer
1. Open your **Portainer Dashboard**.
2. Go to **Images** ➔ Click **Import image** (top action bar next to Build).
3. Select `coa-server-images-update.tar` and click **Upload**.
4. Portainer will unpack and update the local image tags (`coa/ac-authserver:latest`, etc.).

#### Step 3: Recreate Containers with the New Images
1. Navigate to **Stacks** ➔ Click on your stack (e.g., **`coa-repack`**).
2. Click on the **Editor** tab.
3. Without modifying the YAML, click **`Update the stack`** at the bottom.
4. Toggle **Re-pull image** to `OFF` (you already imported the pre-built local image).
5. Click **Update**.

Alternatively, you can recreate the containers individually:
1. In Portainer, go to **Containers**.
2. Select `ac-worldserver` and `ac-authserver`.
3. Click **Recreate** ➔ Toggle **Re-pull image** `OFF` ➔ Click **Recreate**.

Portainer will shut down the old containers and launch new ones using the updated image binaries while preserving all volume mounts.

---

## 4. Applying Database Schema Migrations & SQL Updates

AzerothCore features an integrated database versioning and update system managed by the `ac-db-import` service.

### Automatic Migration Process
Whenever you update your server images and restart the stack:
1. `ac-db-import` starts before `ac-authserver` and `ac-worldserver`.
2. It inspects the `updates` tables in `acore_auth`, `acore_characters`, and `acore_world`.
3. It scans `/azerothcore/source/data/sql/updates` and module update folders for any pending SQL scripts that have not yet been executed.
4. It applies the pending migrations in chronological order and records the hash in the database.
5. Once complete, `ac-db-import` terminates with `Exited (0)`.

### Monitoring Database Migrations in Portainer
To verify migrations completed successfully:
1. Go to **Containers** ➔ Click the **Logs** icon next to **`ac-db-import`**.
2. Look for the completion message:
   ```text
   Applying updates to acore_world...
   Database update finished without errors.
   ```
3. If `ac-db-import` reports errors or fails to exit with code 0, `ac-worldserver` will remain paused (governed by `depends_on: condition: service_completed_successfully`).

---

## 5. Updating Server Configuration Files (`config/`)

Upstream updates occasionally introduce new configuration variables or modify default values in `.conf.dist` files.

### Merging Upstream Configuration Options
1. Review the reference files generated or updated in `./config/`:
   - `config/authserver.conf.dist`
   - `config/worldserver.conf.dist`
   - `config/modules/mod_ascension_compat.conf.dist`
2. Compare the `.dist` file against your active `.conf` file using a diff tool (such as VS Code or `git diff`).
3. Copy new configuration keys into your active `.conf` file.

> [!IMPORTANT]
> **Preserve These Critical CoA Configuration Parameters:**  
> When merging configuration updates, do not overwrite these settings:
> - `BindIP = "0.0.0.0"` in both `authserver.conf` and `worldserver.conf` (required for Docker bridge port forwarding).
> - `AscensionCompat.AllowRemoteClients = 1` in `config/modules/mod_ascension_compat.conf` (required for external client connections).
> - `PlayerStart.CustomSpells = 1` and `Ascension.Manastorm.Enable = 1` (required for CoA custom class mechanics).

After modifying any `.conf` file, restart the respective service in Portainer or CLI:
```bash
docker compose restart ac-worldserver
```

---

## 6. Updating Game Data Assets (`ac-data-init`)

If a major Conquest of Azeroth content patch requires updated DBCs, maps, or collision vmaps:

1. **Obtain the New Asset Release:**
   Obtain the new `Data.zip` URL and calculate its SHA-256 checksum:
   ```powershell
   Get-FileHash -Algorithm SHA256 Data.zip
   ```

2. **Update Environment Variables in Compose / Portainer Web Editor:**
   Update the `ac-data-init` service definition:
   ```yaml
   environment:
     DATA_URL: "https://your-domain.com/downloads/Data-v2.zip"
     EXPECTED_SHA256: "NEW_SHA256_HASH_HERE"
   ```

3. **Purge the Outdated Data Volume:**
   Because `ac-data-init` checks if `AreaTable.dbc` already exists to prevent unnecessary redownloads, you must purge the old client data volume to trigger the re-download:
   
   **In Portainer:**
   - Go to **Containers** ➔ Stop `ac-worldserver`.
   - Go to **Volumes** ➔ Click on **`ac-client-data`** (or `<stack>_ac-client-data`).
   - Click **Remove**. (Do **NOT** remove `ac-database-data`!).
   - In **Containers**, start `ac-data-init` ➔ It will automatically download the new asset archive, verify SHA-256, and unpack it into a fresh volume.
   - Start `ac-worldserver`.

   **In Local Docker CLI:**
   ```bash
   docker compose stop ac-worldserver
   docker volume rm coa-docker_ac-client-data
   docker compose up -d ac-data-init
   docker compose up -d ac-worldserver
   ```

---

## 7. Updating Portainer CE on the Remote Server

Portainer CE runs as an independent container and can be upgraded without restarting your game server stack or affecting running game containers.

Execute the following commands over SSH on the remote host:

```bash
# 1. Stop and remove the existing Portainer container
docker stop portainer
docker rm portainer

# 2. Pull the latest Portainer CE image
docker pull portainer/portainer-ce:latest

# 3. Launch the updated Portainer container (re-attaching the persistent data volume)
docker run -d \
  -p 8000:8000 \
  -p 9443:9443 \
  --name portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

> [!NOTE]
> By re-mounting `-v portainer_data:/data`, all existing user credentials, environment configurations, and stack definitions (`coa-repack`) are fully preserved.

---

## 8. Updating Docker Engine on the Host OS

To ensure security patches and Docker daemon stability on your Linux VPS:

### Ubuntu / Debian:
```bash
# 1. Update package indices
sudo apt-get update

# 2. Upgrade Docker Engine and plugins
sudo apt-get install --only-upgrade -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 3. Verify Docker daemon status
sudo systemctl status docker
```

Running containers will continue executing uninterrupted if Docker's `live-restore` feature is enabled (`/etc/docker/daemon.json` containing `{"live-restore": true}`). Otherwise, containers will automatically restart according to their `restart: unless-stopped` policy.

---

## 9. Disaster Recovery & Rollback Procedures

If an update introduces game-breaking bugs, crashes worldserver on startup, or corrupts data:

### Scenario A: Rolling Back Server Images
If the new C++ build fails or crashes:
1. Re-import your previous working `.tar` image archive into Portainer.
2. In Portainer, go to **Containers** ➔ Select `ac-worldserver` and `ac-authserver` ➔ Click **Recreate**.
3. The server immediately reverts to the previous working binary build.

### Scenario B: Restoring Database from Backup
If a migration or bad SQL script corrupted database tables:

1. **Stop the game server containers:**
   ```bash
   docker compose stop ac-worldserver ac-authserver
   ```
   *(Or click **Stop** on both containers in Portainer)*

2. **Restore the database dump:**

   **Local CLI:**
   ```powershell
   # Windows PowerShell:
   Get-Content "backup_coa_20260914.sql" | docker exec -i ac-database /usr/bin/mysql -u root -ppassword
   ```
   ```bash
   # Linux Bash (uncompressed or compressed):
   gunzip < backup_coa_20260914.sql.gz | docker exec -i ac-database /usr/bin/mysql -u root -ppassword
   ```

   **Portainer Console on `ac-database`:**
   If you created `/var/lib/mysql/pre_update_backup.sql`:
   ```bash
   mysql -u root -ppassword < /var/lib/mysql/pre_update_backup.sql
   ```

3. **Restart the server stack:**
   ```bash
   docker compose start ac-authserver ac-worldserver
   ```

---

## 10. Routine Maintenance Checklist

Perform these routine health tasks monthly:

- [ ] **Create an off-site database backup:** Export `acore_characters` and `acore_auth` and store them in safe cold storage.
- [ ] **Clean Docker build cache and dangling images:**
  ```bash
  docker image prune -f
  docker builder prune -f
  ```
- [ ] **Check database disk space:**
  ```bash
  docker exec -it ac-database mysql -u root -ppassword -e "SELECT table_schema AS 'Database', ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)' FROM information_schema.TABLES GROUP BY table_schema;"
  ```
- [ ] **Inspect log files for recurring errors:** Check `./logs/worldserver.log` or view container logs in Portainer for uncaught exception traces or missing spell script warnings.
