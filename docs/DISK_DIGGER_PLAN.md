# Disk Digger plan

Goal: the Disk Map explains **every byte** the disk reports as used, points at what is unusually big
and why, and makes deleting important data slow and informed.

Real case that started this (2026-11-25): disk 245 GB, 238 GB used, macOS showed Users = 47.7 GB.
The rest was `/opt/homebrew/var/mysql` = 70 GB: 1,484 leftover `dental_*` test databases
(~45 MB each) + 6.2 GB binlogs + 6.4 GB `mysql.ibd`. Plus 33 GB apps (XAMPP 16 GB), Preboot 9.7 GB.

## Why the current Disk Map misses it

| Gap | Cause in code |
|---|---|
| Default root is Home, so `/opt`, `/Applications`, `/private` are never seen | `DiskMapModel.init` picks `.home` |
| 1,484 × 45 MB folders all fold into one grey "Other (1484 items)" | `DiskMapBuilder.fold`: each child < 0.5 % share → folded, no hint what they are |
| Unreadable folders count as 0 B, silently | `FTS_DNR` closes the frame with no record |
| Preboot, Recovery, VM, System volumes, APFS snapshots, purgeable space are not in the tree | Builder only walks one file tree; no container accounting |
| Map total never matches "used" from Finder/`df`, so the user cannot tell what is missing | No reconciliation row |
| Big blocks have no explanation ("what is mysql, can I delete it?") | No path knowledge |

## What we build

### 1. Full-disk accounting (DusterCore `Explore/DiskAccounting.swift`)
- Read the APFS container (`diskutil apfs list -plist`) → used, free, each volume's consumed bytes.
- Rows: Data volume (scanned tree), System, Preboot, Recovery, VM, local snapshots (helper already
  lists them), purgeable, **Unreadable** (sum of skipped folders), **Unexplained** = used − everything else.
- The map shows these as top-level blocks when root is the boot volume, so blocks add up to "used".
- Disk Map opens on the whole Mac (boot volume) by default (owner decision, 2026-11-25); Home stays one click away.

### 2. Unreadable folders
- Builder records each `FTS_DNR`/`FTS_ERR` path in `DiskNode.unreadable`.
- "Scan with admin rights" button sends those paths to the privileged helper: new allowlisted XPC
  method `sizeTree(paths:)` that returns sizes only (read-only, no delete).

### 3. Insights: "why is this big" (DusterCore `Explore/Insights/`)
Run over the finished tree; each finding has bytes, paths, plain-language reason, safe action.
- **Clone sets**: ≥ 20 siblings sharing a name prefix (`dental_t_*_test_N`) → "1,484 copies, 65 GB".
  Folded "Other" blocks with a clone set get a label like "1,484 dental_* folders".
- **Database data dirs**: detect MySQL/MariaDB (`ibdata1`/`mysql.ibd`, `#innodb_redo`), Postgres
  (`PG_VERSION`), Redis, Mongo. Show per-database size, binlog total, server running or not.
- **Known heavy paths** from a catalog (below): Docker VM disk, simulators, Xcode DerivedData,
  Android SDK, XAMPP, Homebrew cache, `node_modules` farms, model weights.
- Insights panel lists findings by size; click → jump to the block.

### 4. Path knowledge catalog (DusterCore `Rules/PathKnowledge.swift`)
Data only, same style as `RuleCatalog`. Each entry: glob, title, owner tool, "what uses it",
"what breaks if deleted", risk level, recommended safe action (command or in-app action).
Example: `/opt/homebrew/var/mysql/*` → owner MySQL (Homebrew), "every local MySQL database lives
here; deleting folders corrupts the server", risk Critical, action "drop the databases you don't need".

### 5. Delete risk rules (DusterCore `Clean/DeleteRisk.swift`)
Every user-selected delete from the map / finder is graded before the confirm sheet:

| Level | Examples | Confirmation |
|---|---|---|
| Blocked | anything `DenyGuard` refuses today | cannot delete, shows the reason |
| Critical | database data dirs, Docker VM disk, `~/Library/Application Support/<app>`, git repos with unpushed work, a running app's data, keychains-adjacent | sheet shows **possible usage** (owner, what breaks, running process using it, last modified), offers the safe action first, and needs the user to **type the folder name** |
| Review | app bundles, SDKs, large user files | sheet with usage info + normal confirm |
| Safe | caches and rebuildable artifacts already in `RuleCatalog` safe tier | normal confirm |

**OS files are always Blocked** (owner rule, 2026-11-25): nothing that can break macOS is deletable
from the map, at any level, even with typed confirmation or admin rights. `DenyGuard` gains these to
its existing `/System`, `/usr`, `/bin`, `/sbin`, `/Library` list:
`/private` (except `/private/tmp` contents), `/etc`, `/var`, `/tmp` itself, `/cores` itself, `/opt` and
`/opt/homebrew` themselves (their contents grade normally), `/Applications` apps that ship with macOS
(signed by Apple, e.g. Safari), `/Volumes` itself, every non-Data APFS volume (System, Preboot,
Recovery, VM), and `/usr/local` itself. Snapshots and system caches stay with the existing helper
flows only. The map still shows these blocks, with a lock icon and the reason on hover.

"Possible usage" comes from: PathKnowledge entry, `ProcessProbe` (process with open files under the
path), owning `.app` / brew formula, `git status` for repos, newest file date.
Critical items always go to Trash (instant delete untickable), and Trash for DB dirs is refused while
the server runs.

### 6. Safe actions for databases
The app drops databases itself (owner decision, 2026-11-25). For MySQL clone sets: list databases,
multi-select (nothing pre-selected; a "Select clone set" button), show the exact SQL and the total size, confirm, then run
`DROP DATABASE` for each through the local `mysql` client and `PURGE BINARY LOGS BEFORE NOW()`.
Each drop is logged to `CleanLog`; the sheet reports dropped, failed and space freed. Drops are
not undoable, so the confirm says so. Never delete InnoDB files directly.

### 7. CLI
`devduster dig [path]` prints the accounting table + top insights (same core, text output).

## Layering
- DusterCore: `DiskAccounting`, builder changes, `Insights/*`, `PathKnowledge`, `DeleteRisk`,
  `MySQLInspector` (runs client, parses output). All logic and tests here.
- Helper: `sizeTree(paths:)` only, added to `HelperAllowlist`.
- App: `DiskMapModel` holds accounting + insights; new `InsightsPanel`, `CriticalDeleteSheet`,
  `DatabaseCleanupSheet`; `DiskMapView` draws system rows and labelled clone blocks.
- CLI: `DigCommand`.

## Tests (spec)
- `DiskAccountingTests`: given container plist fixture (245.1 GB, volumes as above) and a scanned
  tree of 170 GB → rows sum to used; Unexplained = used − others; never negative.
- `DiskMapBuilderTests`: unreadable folder → listed in `unreadable`, bytes 0, scan continues.
- `CloneSetTests`: 1,484 `dental_t_x_test_N` + 3 unrelated → one set of 1,484, prefix `dental_`;
  19 siblings → no set; mixed prefixes `a_1..a_30`, `b_1..b_30` → two sets.
- `DatabaseDetectorTests`: fixture dirs with `mysql.ibd` → MySQL, `PG_VERSION` → Postgres, none → nil.
- `PathKnowledgeTests`: `/opt/homebrew/var/mysql/foo` → MySQL entry, Critical; `~/Library/Caches/x` → Safe.
- `OSProtectionTests`: `/private/var/db/x`, `/etc/hosts`, `/Applications/Safari.app`,
  `/System/Volumes/Preboot/x`, `/opt`, `/usr/local` → Blocked; `/private/tmp/x`,
  `/opt/homebrew/var/mysql/dental_t_1`, `/Applications/XAMPP` → not Blocked.
- `DeleteRiskTests`: DenyGuard refusal → Blocked; DB dir → Critical; `node_modules` → Safe;
  `.app` → Review; repo with unpushed commit → Critical; typed name must match exactly (case-sensitive).
- `MySQLInspectorTests`: parse fixture `SHOW DATABASES` + sizes output; system DBs
  (`mysql`, `sys`, `information_schema`, `performance_schema`) never offered for drop.

## Work split (waves)
1. **Wave 1 (parallel, separate files)**
   - Core accounting + builder unreadable tracking + tests — Antigravity Hydrogen.
   - PathKnowledge catalog + DeleteRisk + tests — Claude Sonnet session (safety logic).
   - Clone sets + DB detector + MySQLInspector + tests — Antigravity Hydrogen.
2. **Wave 2**: helper `sizeTree` (Opus review: privileged), App UI (map rows, insights panel,
   critical/DB sheets) — Hydrogen; CLI `dig` — opencode flash-lite.
3. **Wave 3**: Claude runs the app on this Mac, checks the map adds up to `df` used, finds the
   MySQL clone set, and walks the Critical delete flow without confirming.

