# DevDuster: personal Mac cleaner (SwiftUI)

## Context
Both disks are almost full. **Internal: 3.2 GB free of 228 GB. Storage (external APFS over USB): 345 MB free of 112 GB.** Most of it is dev data that can be regenerated:

| Where | Size |
|---|---|
| `/Volumes/Storage/.gradle` (symlinked from `~`) | 22 GB |
| `/Volumes/Storage/Android/sdk` | 19 GB |
| Project artifacts in `/Volumes/Storage/Projects` (build 4.2, node_modules 5.1, Pods 3.5, .gradle 2.0, .dart_tool 1.5) | ~16 GB |
| `~/Library/Caches` | 13 GB |
| Docker (`~/Library/Containers/com.docker.docker`) | 9.5 GB |
| `/Volumes/Storage/.android` (AVDs) | 8.9 GB |
| `/Volumes/Storage/flutter` | 7.9 GB |
| CoreSimulator 7.0 / iOS DeviceSupport 6.6 / DerivedData 4.5 GB | 18 GB |
| `.pub-cache` 5.9, Logs 2.2, npm 1.2 GB | 9 GB |

Goal: an unsandboxed, Full Disk Access, root-capable SwiftUI app for the user only. It cleans by allowlisted rules across the internal disk and external volumes, and adds a disk map, a large/old file finder and toggleable automation. Claude supervises and does not write the code.

Decisions already made: SwiftUI. Signed with the **Appentium LLC team (4GAP4FSZZS)**, already in Xcode. "Move to Trash" is checked by default and can be unticked for instant delete. Disk map and finder are in v1. Every automation has an on/off toggle in Settings.

## Step 0: Emergency space recovery (Claude runs it, before any build)
Xcode and the agent sessions can't build with 3 GB free. Claude shows the exact list with sizes, the user approves each batch, then Claude runs it using each tool's own cleanup command wherever one exists:
- **Safe:** DerivedData, `~/Library/Logs`, `xcrun simctl delete unavailable`, `~/.gradle/daemon` logs, `~/.gradle/caches/build-cache-*`.
- **Review:** old `~/.gradle/wrapper/dists` versions; `~/.gradle/caches/` (Gradle re-downloads); `iOS DeviceSupport` except the newest version; the biggest `~/Library/Caches/*` subfolders; `docker system prune`; build artifacts in projects untouched for 30+ days.
- **Caution, user picks each:** AVDs, old SDK system-images and NDKs, `dart pub cache clean`.

Target: at least 25 GB free on internal and at least 15 GB on Storage.

## Architecture
Repo: `/Volumes/Storage/Projects/appentium/Projects/cleanmymac`. `git init` first, and every work package gets its own branch or worktree. XcodeGen (`brew install xcodegen`) generates the project from `project.yml`, so agents never edit `.pbxproj`. Bundle prefix `com.appentium.devduster`, deployment target macOS 27, Swift 6 strict concurrency.

```
project.yml
Packages/DusterCore/            # local SwiftPM package: all logic, no UI
  Sources/DusterCore/
    Scan/        Scanner (fts / getattrlistbulk, parallel, prunes matched dirs), SizeCalculator (allocated size, inode dedupe)
    Rules/       Rule model, RuleCatalog (built-in rules), ProjectArtifactMatcher (marker-file logic)
    Clean/       Cleaner (trash vs delete), DenyGuard (hard never-delete list), CleanLog
    Volumes/     VolumeService (internal + external, read-only/NTFS detection, per-volume .Trashes size + empty)
    Explore/     DiskMapBuilder (tree of sizes), LargeFileFinder (size/age filters)
    Privileged/  HelperClient (XPC protocol shared with the helper)
  Tests/DusterCoreTests/        # temp-dir fixtures, never touches real paths
App/      SwiftUI app: Dashboard, Cleaner, DiskMap (squarified treemap + drill-down), Finder, Settings, FDA onboarding, MenuBarExtra
Helper/   privileged daemon via SMAppService + NSXPCConnection; checks the caller's code signature; own path allowlist
CLI/      `duster` (swift-argument-parser): scan / clean --tier safe; used by the scheduled LaunchAgent
```

### Rule model (the safety core)
Each rule has an `id`, `tier` (safe / review / caution), a root path or project marker, a regenerate note, an optional `minAgeDays`, and an optional guard (for example: skip `~/.gradle/caches` while a Gradle daemon is running, or run `gradle --stop` first). Docker is never deleted as files; only `docker system prune` is used.
- Project artifacts are deleted only when the matching marker sits next to them. `build/` and `.dart_tool/` need `pubspec.yaml`; `.gradle/` and `build/` need `build.gradle(.kts)`; `Pods/` needs `Podfile`; `node_modules/` needs `package.json`. The scanner works on all mounted volumes and skips projects modified in the last N days (a setting, default 14).
- **Flutter Projects section** (its own sidebar entry and its own CLI command, `duster flutter`). It lists every Flutter project found on all volumes, meaning any folder with a `pubspec.yaml` that has a `flutter:` dependency. For each project it shows the path, last activity, and the sizes of `.dart_tool/`, `build/` and optionally `ios/Pods`, `ios/.symlinks` and `android/.gradle`. Checkboxes work per project and per folder, with Select all and Select stale. It reuses ProjectArtifactMatcher plus a `FlutterProjectScanner` in `Rules/`, and goes through the same Cleaner and DenyGuard as everything else.
- **DenyGuard** runs on every path in `Cleaner` as the last check. It refuses anything outside a rule's root, and it refuses Keychains, `Mobile Documents`, Photos/Messages/Mail libraries, `/System`, the volume root, and the user's home itself, even when the UI asks for it.
- The user always sees a preview before anything is removed. Trash is the default; instant delete is a per-run toggle. Every removal goes to `~/Library/Logs/DevDuster/clean.log`.
- Items trashed on an external volume land in `/Volumes/X/.Trashes/501` and free nothing until that trash is emptied, so the Dashboard shows each volume's trash size with an Empty button.

### Root helper (SMAppService daemon)
It runs a fixed set of operations only: delete local Time Machine snapshots, clean `/Library/Caches`, clean `/private/var/log` archives, and empty root-owned volume trashes. It takes no free-form paths beyond its allowlist. The app checks for Full Disk Access by probing a protected path and deep-links to System Settings → Privacy → Full Disk Access.

### Automation (each one toggleable in Settings)
- Menu bar free-space meter for each volume.
- Low-space notification below a threshold (default 20 GB internal, 10 GB external).
- Scheduled "clean Safe tier" through a LaunchAgent that runs the `duster` CLI (off by default).
- Also in Settings: excluded paths and the stale-project age.

## Work packages and who builds them
Claude starts each session, reviews every diff (coding rules from GEMINI.md, deletion safety, privacy), runs the gates, and sends every bug back until it is verified fixed. If a model fails the same issue twice, Claude takes that task over in its own session (Opus or Sonnet).

| WP | Scope | Builder | Depends on |
|---|---|---|---|
| 0 | Scaffold: git, `project.yml`, 4 targets, signing with team 4GAP4FSZZS, `make build` / `make test` scripts | Claude Code **Sonnet** | Step 0 |
| 1 | DusterCore: Scanner, SizeCalculator, Rules + catalog, ProjectArtifactMatcher, Cleaner + DenyGuard + log, VolumeService; full unit tests | Claude Code **Opus** (deletion-critical) | WP0 |
| 2 | App shell, Dashboard, Cleaner UI (preview, tier groups, Trash toggle), FDA onboarding | Antigravity **gemini-4-hydrogen-high** | WP1 API |
| 3 | DiskMapBuilder + treemap view, LargeFileFinder + view (reveal in Finder, trash) | Antigravity **gemini-4-hydrogen-high** | WP1 API |
| 4 | Privileged helper, XPC protocol, SMAppService registration, caller-signature check | Claude Code **Opus** | WP1 |
| 5 | Settings, MenuBarExtra, notifications, `duster` CLI, LaunchAgent install/remove | Claude Code **Sonnet** | WP2 |

WP2, WP3 and WP4 run in parallel in separate worktrees once WP1 is merged; their files don't overlap. Claude merges each branch only after review passes.

## Verification
- **Gates for every WP:** `make build` (xcodebuild, warnings treated as errors in DusterCore) and `make test` both pass. Then Claude reads the diff.
- **DusterCore tests** build a fake home and fake volume in a temp dir and check four things: marker-based matching (a `build/` with no marker is never matched); DenyGuard refusing every protected path; trash vs delete; and that hard links are counted once.
- **Dry run on the real disks:** run `duster scan` on `~` and `/Volumes/Storage` and compare its totals with the `du` figures above, within about 5%.
- **Manual app pass:** Claude launches the app and screenshots the Dashboard, Cleaner preview, Disk Map and Finder. Then it does one real clean of the Safe tier to Trash, checks the files are in Trash and the log is written, and restores one item to prove recovery works.
- **Helper:** register it, approve it in Login Items, delete one local snapshot, and confirm with `tmutil listlocalsnapshots /`.
