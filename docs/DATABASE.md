# Conquest of Azeroth (CoA) — Database Architecture & Installation Guide

This document provides a comprehensive technical reference for the database architecture and installation process of the Docker-based AzerothCore WotLK / Conquest of Azeroth (CoA) repack.

---

## 1. Executive Architecture Overview

The database backend for the Conquest of Azeroth server is orchestrated by MySQL 8.4 LTS inside the `ac-database` container. The system utilizes three logically separated schemas adhering to standard TrinityCore/AzerothCore architectural separation:

```text
                           ┌────────────────────────┐
                           │      ac-database       │
                           │      (MySQL 8.4)       │
                           └───────────┬────────────┘
                                       │
            ┌──────────────────────────┼──────────────────────────┐
            ▼                          ▼                          ▼
   ┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐
   │   acore_auth    │        │acore_characters │        │   acore_world   │
   │  Authentication │        │ Player Entities │        │ Game Rules &    │
   │  & Realm Registry│       │ & Collections   │        │ CoA Content     │
   └─────────────────┘        └─────────────────┘        └─────────────────┘
```

### Key Infrastructure Specifications
- **Database Engine:** MySQL 8.4 Community Server (LTS)
- **Default Storage Engine:** InnoDB (Strict row-level locking and transaction support)
- **Character Set & Collation:** `utf8mb4` / `utf8mb4_unicode_ci`
- **Container Listening Port:** `3306` (Mapped to host via `${DOCKER_DB_EXTERNAL_PORT:-3306}`)
- **Persistence:** Dedicated Docker volume `ac-database-data` mapped to `/var/lib/mysql`
- **Authentication Model:**
  - `root`: Administrative access (configured via `DOCKER_DB_ROOT_PASSWORD`)
  - `acore`: Application user with granted privileges on `acore_auth`, `acore_characters`, and `acore_world`

---

## 2. Database Schemas & Data Inventory

### 2.1 `acore_auth` — Authentication & Realm Management

The `acore_auth` database manages account identities, cryptographic authentication proofs (SRP-6), security access levels, realm registration, and global access control lists.

#### Core Tables & Responsibilities
| Table | Description | Key Columns |
| :--- | :--- | :--- |
| `account` | Player and GM accounts, SRP-6 password verifiers (`verifier`, `salt`), session keys, email, and lock states | `id`, `username`, `salt`, `verifier`, `session_key` |
| `account_access` | Security levels assigned to accounts (0 = Player, 1 = Moderator, 2 = Gamemaster, 3 = Administrator) | `AccountID`, `SecurityLevel`, `RealmID` |
| `realmlist` | Registered game server realms displayed on the client realm selection screen | `id`, `name`, `address`, `localAddress`, `port`, `icon`, `flag`, `gamebuild` |
| `rbac_*` | Role-Based Access Control permissions, linked permissions, and security hierarchy | `rbac_permissions`, `rbac_account_permissions`, `rbac_default_permissions` |
| `build_info` | Client build compatibility table defining supported client version ranges (e.g., build 12340 for 3.3.5a) | `build`, `majorVersion`, `minorVersion`, `bugfixVersion`, `hotfixVersion` |
| `ip_banned` / `account_banned` | Security ban enforcement by IP address or account ID | `ip`, `bandate`, `unbandate`, `bannedby`, `banreason` |
| `motd` | Message of the day broadcasts displayed in chat upon player login | `realmid`, `text` |
| `uptime` | Uptime and performance history for registered realms | `realmid`, `starttime`, `uptime`, `maxplayers` |
| `updates` / `updates_include` | AzerothCore automated update migration journal | `name`, `hash`, `state`, `timestamp`, `speed` |

#### Repack Baseline State
- **Accounts:** Contains 1 default administrative account: `local` (Password: `local`, GM Level: 3).
- **Realmlist:** Contains 1 realm entry: `AzerothCore` targeting port `8085` with icon `0` (Normal) and timezone `1` (Development).

---

### 2.2 `acore_characters` — Player Persistence & Custom Collections

The `acore_characters` database stores dynamic player progression, character states, inventories, social structures, and custom Ascension/CoA account-wide collections.

#### Standard AzerothCore Persistence Tables
- **Entities:** `characters`, `character_stats`, `character_aura`, `character_glyphs`, `character_homebind`
- **Progression:** `character_queststatus`, `character_queststatus_daily`, `character_skills`, `character_spell`, `character_talent`, `character_achievement`
- **Inventory & Economy:** `character_inventory`, `item_instance`, `auctionhouse`, `mail`, `mail_items`
- **Social & Grouping:** `guild`, `guild_member`, `guild_bank_tab`, `group`, `group_member`, `character_social`, `arena_team`, `arena_team_member`

#### Custom Conquest of Azeroth / Ascension Tables
Conquest of Azeroth extends the character database with customized schema extensions defined by `mod-ascension-compat`:

```text
┌──────────────────────────────────────────────┐
│        Custom Collection Architecture        │
├──────────────────────────────────────────────┤
│  account_appearance_collection               │  <-- Account-wide transmog unlocks
│  account_vanity_collection                   │  <-- Account-wide vanity items & mounts
│  character_appearance                        │  <-- Active character transmog slots
│  character_appearance_settings               │  <-- Per-character visibility toggles
├──────────────────────────────────────────────┤
│        Custom Manastorm Progression          │
├──────────────────────────────────────────────┤
│  ascension_manastorm_loadout                 │  <-- Saved loadout profiles
│  ascension_manastorm_xp                      │  <-- Mode-specific experience
│  ascension_manastorm_clear                   │  <-- Dungeon depth completion records
│  ascension_manastorm_bonus                   │  <-- Active rogue-lite buffs/bonuses
│  ascension_manastorm_cache                   │  <-- Rewarded vanity & progression cache
├──────────────────────────────────────────────┤
│        Bug Reporting Subsystem               │
├──────────────────────────────────────────────┤
│  bugreport                                   │  <-- In-game report spooling queue
└──────────────────────────────────────────────┘
```

1. **`account_appearance_collection`**:
   - Stores unlocked item appearances tied to the master account ID rather than individual characters.
   - Columns: `account_id` (INT), `appearance_id` (INT), `source_item` (INT).
2. **`account_vanity_collection`**:
   - Stores unlocked vanity items, companion pets, and mounts across the account.
   - Columns: `account_id` (INT), `item_id` (INT).
3. **`character_appearance`**:
   - Stores active transmogrification overrides per equipment slot category for each character.
   - Columns: `guid` (INT), `category_id` (TINYINT), `appearance_id` (INT).
4. **`character_appearance_settings`**:
   - Visual toggle preferences per character.
   - Columns: `guid` (INT), `can_see_item` (TINYINT), `can_see_spell` (TINYINT).
5. **`ascension_manastorm_*`**:
   - Five dedicated tables tracking loadouts, depth progress, experience, and rewards for the integrated Manastorm game mode (`Ascension.Manastorm.Enable = 1`).
6. **`bugreport`**:
   - In-game queue capturing player bug reports submitted via the custom client interface (`CoABugReport.Enable = 1`).

---

### 2.3 `acore_world` — Static Game Rules & Custom CoA Content

The `acore_world` database contains the static game mechanics, world layout, quest definitions, spell attributes, NPC templates, loot tables, and Conquest of Azeroth class definitions.

#### Standard AzerothCore Content Tables
- **World Entities:** `creature_template`, `creature`, `gameobject_template`, `gameobject`
- **Quests & Scripts:** `quest_template`, `smart_scripts`, `waypoint_data`, `game_tele`
- **Items & Spells:** `item_template`, `spell_group`, `spell_area`, `spell_script_names`
- **Loot Tables:** `creature_loot_template`, `gameobject_loot_template`, `item_loot_template`, `reference_loot_template`
- **DBC Mirrors:** Tables mirroring client DBC data (e.g., `areatable_dbc`, `faction_dbc`, `map_dbc`, `spell_dbc`) for fast relational SQL queries.

#### Custom Conquest of Azeroth Schema & Content Extensions
1. **`ascension_custom_class`**:
   Defines the 21 custom Conquest of Azeroth classes, mapping their internal class IDs (12–32) to fallback base classes, power types, and primary attributes:
   - `12` Barbarian (Rogue fallback, Energy power, Agility primary)
   - `13` Witch Doctor (Shaman fallback, Mana power, Intellect primary)
   - `14` Demon Hunter / Felsworn (Rogue fallback, Energy power, Agility primary)
   - `15` Witch Hunter (Hunter fallback, Mana power, Agility primary)
   - `16` Stormbringer (Shaman fallback, Mana power, Intellect primary)
   - `17` Fleshwarden / Knight of Xoroth (Warrior fallback, Rage power, Strength primary)
   - `18` Guardian (Warrior fallback, Energy power, Strength primary)
   - `19` Monk / Templar (Rogue fallback, Energy power, Agility primary)
   - `20` Son of Arugal / Bloodmage (Druid fallback, Rage power, Agility primary)
   - `21` Ranger (Hunter fallback, Focus power, Agility primary)
   - `22` Chronomancer (Priest fallback, Mana power, Spirit primary)
   - `23` Necromancer (Warlock fallback, Runic Power, Intellect primary)
   - `24` Pyromancer (Mage fallback, Mana power, Intellect primary)
   - `25` Cultist (Paladin fallback, Mana power, Strength primary)
   - `26` Starcaller (Druid fallback, Energy power, Intellect primary)
   - `27` Sun Cleric (Priest fallback, Mana power, Intellect primary)
   - `28` Tinker (Hunter fallback, Mana power, Agility primary)
   - `29` Prophet / Venomancer (Shaman fallback, Mana power, Intellect primary)
   - `30` Reaper (Rogue fallback, Runic Power, Agility primary)
   - `31` Wildwalker / Primalist (Druid fallback, Mana power, Agility primary)
   - `32` Spirit Mage / Runemaster (Shaman fallback, Mana power, Intellect primary)
2. **`ascension_custom_class_race`**:
   Enforces race eligibility restrictions for each of the 21 custom classes across all playable races (Human, Orc, Dwarf, Night Elf, Undead, Tauren, Gnome, Troll, Blood Elf, Draenei).
3. **`item_template_ascension_compat`**:
   Contains thousands of visual item records synchronized with the client's custom `Item.dbc` display IDs (e.g., `Ascension Appearance X`), ensuring the custom client can render appearances without crashing or modifying stock WotLK items.

---

## 3. Database Installation & Assembly Pipelines

### 3.1 Upstream AzerothCore Database Assembly Pipeline

In a stock AzerothCore build, the database is initialized through the `db_assembler.sh` tool or the `ac-db-import` utility:

```text
┌─────────────────────────────────────────────────────────────┐
│ 1. Base Schemas                                             │
│    source/data/sql/base/db_auth/auth_database.sql           │
│    source/data/sql/base/db_characters/characters_database.sql│
│    source/data/sql/base/db_world/world_database.sql         │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Core Updates                                             │
│    source/data/sql/updates/db_auth/*.sql                    │
│    source/data/sql/updates/db_characters/*.sql              │
│    source/data/sql/updates/db_world/*.sql                   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Module Migrations                                        │
│    source/modules/mod-*/data/sql/db-characters/*.sql        │
│    source/modules/mod-*/data/sql/db-world/*.sql             │
└─────────────────────────────────────────────────────────────┘
```

The database assembler concatenates base schemas and applies pending SQL updates sequentially. It records each applied script hash in the `updates` table to avoid redundant executions.

---

### 3.2 The Conquest of Azeroth Repack Snapshot Mechanism

The Conquest of Azeroth repack adopts a snapshot-based distribution mechanism:

```text
      Database/Clean/databases.sql.gz (~93.6 MB compressed)
                               │
            ┌──────────────────┴──────────────────┐
            ▼                                     ▼
   Database/Clean/snapshot.json            reset-database.py
   (SHA-256 validation & row counts)     (Binary stream restoration)
                               │
                               ▼
                    acore_auth, acore_characters,
                     acore_world fully populated
```

#### Snapshot Specifications
- **Clean Archive:** `Database/Clean/databases.sql.gz` (~93.6 MB compressed, ~1.1 GB uncompressed SQL dump).
- **Metadata File:** `Database/Clean/snapshot.json` stores:
  - Format version: `1`
  - Targets: `acore_auth`, `acore_characters`, `acore_world`
  - Expected `gzipSHA256`: `d59e5938295eaba7f44fbbdc8005f6ff5a46e7cd995c58893055218e5e8f3ec0`
  - Expected `sqlSHA256`: `a99090c37c79169503d0869799c034b0f288186f29415866a24f897839e0e263`
  - Comprehensive inventory of 480+ tables and strict baseline row counts.
- **Factory Reset Routine (`reset-database.py`):**
  - Confirms no game servers are connected to MySQL.
  - Takes a precautionary safety backup in `Database-Backups/<timestamp>`.
  - Executes `mysql --binary-mode` to stream `databases.sql.gz` into the database.
  - Re-verifies table counts against `snapshot.json`.

#### Why Automatic SQL Updates Are Disabled
In both `authserver.conf` and `worldserver.conf`, the updater settings are intentionally set to:
```ini
Updates.EnableDatabases = 0
Updates.AutoSetup = 0
```
**Rationale:**
1. The CoA repack database is already at the target schema version, including all custom CoA tables and migrations.
2. If AzerothCore's internal `Updates.EnableDatabases` is enabled, the core attempts to reconcile its git-based migration hashes against the database's `updates` table. When custom tables, modified schemas, or rebased migrations exist, the core halts startup on hash mismatch errors.
3. Managing schema updates externally via controlled migration scripts preserves custom content and prevents data corruption.

---

## 4. Docker Database Operations & Administration

### 4.1 Inspecting the Database via Docker CLI

To open an interactive MySQL CLI session inside the running container:
```bash
docker compose exec -it ac-database mysql -u root -ppassword
```

To run a quick query without entering the interactive shell:
```bash
docker compose exec ac-database mysql -u root -ppassword -e "SELECT id, name, address, port FROM acore_auth.realmlist;"
```

### 4.2 Connecting with External Database GUI Clients

You can connect external tools (HeidiSQL, DBeaver, Navicat, DataGrip) directly to the database:
- **Hostname:** `127.0.0.1` (or `localhost`)
- **Port:** `3306` (or `${DOCKER_DB_EXTERNAL_PORT}`)
- **User:** `root`
- **Password:** `password` (or `${DOCKER_DB_ROOT_PASSWORD}`)
- **Databases:** `acore_auth`, `acore_characters`, `acore_world`

### 4.3 Database Backup & Restore

#### Backing Up All Three Databases
```bash
# Bash / Linux
docker compose exec ac-database mysqldump -u root -ppassword \
  --single-transaction --quick --hex-blob --routines --triggers \
  --databases acore_auth acore_characters acore_world | gzip > coa_database_backup.sql.gz

# PowerShell / Windows
docker compose exec -T ac-database mysqldump -u root -ppassword `
  --single-transaction --quick --hex-blob --routines --triggers `
  --databases acore_auth acore_characters acore_world > coa_database_backup.sql
```

#### Restoring a Database Dump
```bash
# Bash / Linux
gunzip < coa_database_backup.sql.gz | docker compose exec -T ac-database mysql -u root -ppassword

# PowerShell / Windows
Get-Content coa_database_backup.sql | docker compose exec -T ac-database mysql -u root -ppassword
```

---

## 5. Phase 3B Integration Roadmap

The Phase 3A milestone established host-mounted configuration architecture and documented the complete database schema. The upcoming Phase 3B objective will:
1. Ingest the pre-populated `Database/Clean/databases.sql.gz` snapshot into the Docker environment.
2. Automate snapshot initialization during container bootstrap.
3. Validate row counts against `snapshot.json`.
4. Enable the fully populated world, quests, NPCs, custom classes, and the default GM account (`local`/`local`).
