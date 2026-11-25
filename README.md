<p align="center">
  <img src="App/Assets.xcassets/AppIcon.appiconset/icon_128@2x.png" width="128" alt="DevDuster app icon">
</p>

<h1 align="center">DevDuster</h1>

<p align="center">
  A native macOS cleaner built for software developers.<br>
  It finds the gigabytes that Xcode, Android Studio, Flutter, Gradle, CocoaPods and npm leave behind, and removes them safely.
</p>

<p align="center">
  <a href="https://github.com/Appentium/DevDuster/releases/latest"><b>Download the latest release</b></a> · <a href="https://devduster.com">devduster.com</a>
</p>

<p align="center">
  <img src="docs/screenshots/dashboard.png" width="800" alt="Dashboard: disk usage, reclaimable space, cleaning activity and volumes">
</p>

---

DevDuster is a SwiftUI app with a small privileged helper and a `duster` command-line tool.

## Why

General Mac cleaners skip most developer data or treat it as a black box. A developer's disk fills up with build output and caches that can all be regenerated: DerivedData, simulators, Gradle caches, `node_modules`, `.venv`, Cargo and Go caches, editor caches, downloaded AI models. DevDuster covers 30+ tool families: Xcode, Android, Flutter, JavaScript, Python, Rust, Go, Java and Kotlin, PHP, Ruby, .NET, editors such as VS Code, Cursor and JetBrains, AI tools such as Claude Code and Ollama, game engines and DevOps tools. DevDuster knows what each of these is, what rebuilds it, and how risky it is to remove.

## Features

- **Cleaner**: 100+ built-in rules for caches, logs and build output. Each rule says what it is, what regenerates it, and a tier:
  - **Safe**: rebuilt automatically (DerivedData, SwiftPM, CocoaPods, Homebrew, npm, Yarn, pnpm, Bun, pip, uv, Poetry, Cargo, Go build, Composer and NuGet caches, editor and AI tool caches and logs, Gradle build cache).
  - **Review**: re-downloaded or rebuilt on demand (old Gradle caches and wrappers, Maven, Go modules, Conda packages, Playwright browsers, old iOS DeviceSupport, the Dart pub cache, unused Docker data).
  - **Caution**: you pick each item (Ollama, LM Studio and Hugging Face models, AVDs, unused Android system images, old NDKs, build tools and SDK platforms, simulator runtimes, Vagrant boxes, Xcode archives, device backups).
- **Developer Tools**: shows where each tool's storage goes (Android SDK, emulators, Gradle, Xcode, simulators and more) on any drive, split into Safe to clean, Needs review and Essential parts, and lets you clean the safe and reviewable parts in place. Simulators and runtimes are removed through `simctl`.
- **Move Tools**: moves a tool's data (Gradle, npm, pub cache, SDKs, simulators, editor data, AI models and 70+ more) to another APFS drive. It copies, checks every file, leaves a link at the old path so nothing breaks, and only then deletes the old copy. Refuses while any app has files open there, survives a crash mid-move, and every move can be undone.
- **Projects**: finds every code project on every mounted volume (Flutter, Node, Rust, Gradle, Xcode/CocoaPods, Python, .NET, CMake, Unity, Unreal, Elixir, Haskell, Zig and more) and lists only the folders the next build or install recreates, with last activity, per-project select-all and *Select stale*.
- **Project artifacts**: `node_modules`, `.next`, `.venv`, `Pods`, Gradle `build/`, Cargo and Maven `target/`, Composer `vendor/` and more are removed only when the matching marker file (`package.json`, `pyproject.toml`, `Podfile`, `build.gradle`, `Cargo.toml`, `pom.xml`, `composer.json`) sits next to them, and never in projects you touched recently.
- **Uninstaller**: removes apps together with their leftovers, background items and Homebrew packages. It also finds leftovers of apps that are already gone.
- **Disk Map**: a treemap of any folder or volume with drill-down, a minimum size filter, and folders you can exclude from scans.
- **Large Files**: finds large and old files with size and age filters.
- **Sort and select**: Size and Name sorting and Select All / Deselect All across the Cleaner, Uninstaller, Large Files and System lists.
- **System**: local Time Machine snapshots, `/Library/Caches`, rotated system logs and root-owned trash, through a privileged helper with a fixed allowlist.
- **External disks**: scans every mounted volume and shows each volume's trash, with an Empty Trash button.
- **Automation**: a menu bar item and low-space alerts (on by default), and a scheduled clean of the Safe tier (off by default). Each can be turned off in Settings.

## Screenshots

| Cleaner | Projects |
|---|---|
| ![Cleaner](docs/screenshots/cleaner.png) | ![Projects](docs/screenshots/projects.png) |
| **Developer Tools** | **Move Tools** |
| ![Developer Tools](docs/screenshots/developer-tools.png) | ![Move Tools](docs/screenshots/move-tools.png) |
| **Uninstaller** | **Disk Map** |
| ![Uninstaller](docs/screenshots/uninstaller.png) | ![Disk Map](docs/screenshots/disk-map.png) |
| **Large Files** | |
| ![Large Files](docs/screenshots/large-files.png) | |

## Safety

- You always see a preview before anything is removed. **Move to Trash** is on by default; untick it for an instant delete.
- A hard deny list refuses Keychains, iCloud Drive, the Photos, Messages and Mail libraries, `/System`, volume roots and your home folder, even if a rule or the UI asks for them.
- Items that belong to a running app, or caches in use by a running tool (for example a Gradle daemon), are skipped.
- Every removal is logged to `~/Library/Logs/DevDuster/clean.log`.

## Install

1. Download `DevDuster.zip` from the [latest release](https://github.com/Appentium/DevDuster/releases/latest), unzip it, and move **DevDuster.app** to `/Applications`.
2. Open it and grant **Full Disk Access** when asked, so it can measure caches in protected folders.
3. Optional: to use the **System** section, allow DevDuster's helper under **System Settings → General → Login Items & Extensions**.

Or with Homebrew:

```bash
brew tap appentium/devduster https://github.com/Appentium/DevDuster
brew trust --cask appentium/devduster/devduster
brew install --cask devduster
```

Requires macOS 14 Sonoma or later, on Apple silicon or Intel. The app is signed with a Developer ID and notarized by Apple.

### Command line

The `duster` tool ships inside the app:

```bash
/Applications/DevDuster.app/Contents/MacOS/duster scan
```

| Command | What it does |
|---|---|
| `duster scan` | Lists reclaimable items grouped by rule. Read-only. |
| `duster clean` | Cleans the Safe tier. Moves to Trash unless `--delete` is given. |
| `duster system …` | Root-level cleanup through the helper: `status`, `install`, `uninstall`, `snapshots`, `caches`, `logs`, `trash`. Each lists first; `--clean` removes. |

## Build from source

Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
```

```bash
make gen build
```

```bash
make test
```

All scanning and cleaning logic lives in the `DusterCore` Swift package (`Packages/DusterCore`), with tests that run against temporary folders only. The SwiftUI app is in `App/`, the helper in `Helper/` and the CLI in `CLI/`. To sign with your own team, change `DEVELOPMENT_TEAM` in `project.yml`.

### Releasing

Bump `MARKETING_VERSION` in `project.yml`, commit, then run:

```bash
make release
```

It archives the app, signs it with Developer ID, sends it to Apple for notarization, waits for approval, staples the ticket, signs the zip for Sparkle (the private EdDSA key lives in the login Keychain), adds it to the update feed and the Homebrew cask, and publishes `DevDuster.zip` as a GitHub release. The feed (`appcast.xml`) lives in the private website repo, expected next to this one as `../devduster-website` or at `DEVDUSTER_SITE`. If the wait times out, `scripts/release.sh --resume` picks up from the notarization step. It needs the `gh` CLI signed in and the team's Apple ID in Xcode.

## License

MIT, see `LICENSE`.

## Support

Found a bug or want a rule for another tool? [Open an issue](https://github.com/Appentium/DevDuster/issues). For anything else, including security reports, email [info@devduster.com](mailto:info@devduster.com).
