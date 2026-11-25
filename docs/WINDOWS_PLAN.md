# DevDuster for Windows: plan

Updated 2026-11-25 to match Mac 0.2.0. Code is written on the Mac without a compiler; the owner builds and tests it on the Windows PC.

## Decisions
- **Stack:** C# on .NET 10 (LTS), WinUI 3 (Windows App SDK), CommunityToolkit.Mvvm, xUnit.
- **Repo:** this repo, `Windows/` folder. The Mac app stays untouched.
- **Rules:** a separate C# catalog. Almost every path differs from the Mac one.
- **Shipping:** MSIX through the Appentium LLC Microsoft Store account, which also serves `winget`. The Store signs it.
- **Delete:** Recycle Bin by default; permanent delete is opt-in. An item Windows cannot recycle (too big, or a drive with no bin) is refused, never silently deleted.
- **Targets:** Windows 10 22H2+ and Windows 11, x64 and ARM64. No admin rights, except the System page, which asks through UAC.
- **Updates:** the Store updates the app, so there is no Sparkle equivalent.

## Layout
```
Windows/
  DevDuster.slnx
  DevDuster.Core/        net10.0, no Windows APIs
    Rules/ Scan/ Clean/ Explore/ Relocate/ Settings/ Uninstall/ Automation/
  DevDuster.Platform/    net10.0-windows: recycle bin, allocated size, junctions, installed apps, Task Scheduler
  DevDuster.Cli/         duster.exe: scan, clean, dig
  DevDuster.Helper/      native elevated helper for the System page
  DevDuster.App/         WinUI 3, MSIX packaged
  DevDuster.Core.Tests/  xUnit, temporary folders only
```
Core gets every Windows call through a small interface: `IFileRemover`, `IFileMeasure`, `IProcessProbe`, `IJunctionMaker`.

## Mac features and their Windows form
| Mac 0.2.0 | Windows | Phase |
|---|---|---|
| Cleaner, 100+ rules, three tiers | Same tiers, Windows paths | W1, W2 |
| Projects, every project type | Same markers and proofs, minus Xcode-only ones | W1, W2 |
| Developer Tools storage split | Same analyzer, Windows roots | W3 |
| Move Tools | Copy, verify, rename, junction, delete old; journal and undo | W3 |
| Disk Map with size filter and excluded folders | Same; unreadable folders are listed, not counted as 0 | W3 |
| Large Files | Same | W3 |
| Uninstaller | Registry inventory, vendor uninstaller, leftover folders | W4 |
| Dashboard with history | Same | W2 |
| Sort and Select All everywhere | Same | W2, W3 |
| Theme setting | Same (system, light, dark) | W2 |
| Menu bar, low-space alerts | Tray icon and toast | W5 |
| Scheduled Safe clean | Task Scheduler runs `duster clean` | W5 |
| Empty Trash per volume | Recycle Bin size and empty per drive | W5 |
| System section (root helper) | Elevated helper: Windows Update cache, DISM, dumps | W6 |
| Simulators, Xcode, snapshots | Not on Windows | - |
| Disk Digger (planned on Mac) | After it ships on Mac; Docker/WSL `.vhdx`, MySQL, XAMPP | W7 |

## Safety rules (Core)
- Never follow a junction, symlink, mount point or cloud placeholder. Removing a link removes only the link.
- A path is resolved before it is judged, so a linked parent or an 8.3 short name cannot dodge the guard.
- Size is allocated size; hard links count once per scan.
- `DenyGuard` refuses: drive roots and top-level folders of the system drive, `Windows`, `Program Files`, `ProgramData`, the profile folder and its direct children, `AppData` and its first level, OneDrive, `.ssh`, `.gnupg`, credential stores, Store app packages, UNC and device paths, alternate data streams, and anything outside the rule's own pattern.
- Locked files are skipped and reported, never retried.
- Rules skip while their tool is running. Project artifacts need their marker file, and a project with recent edits is left alone.
- Every removal is logged to `%LOCALAPPDATA%\DevDuster\Logs\clean.log`.

## Move Tools on Windows
- Destination must be a local NTFS or ReFS drive other than the source drive.
- Copy to `<dest>.devduster-partial`, compare every file, rename the source to `.devduster-old`, then make a junction. Junctions need no admin rights.
- Windows refuses to rename a folder with open files; that is the in-use check. The renamed tree is compared again before the old copy goes, so a late write aborts the move.
- The journal is written before each step, and `Recover()` runs at launch.

## Phases
- **W0 setup (owner, Windows PC):** Visual Studio 2026 with .NET desktop, WinUI and Desktop development with C++ workloads (plus the ARM64 C++ tools for ARM64), reserve "DevDuster" in Partner Center.
- **W1:** Core, Platform, CLI, tests.
- **W2:** app shell, Dashboard, Cleaner, Projects, Settings.
- **W3:** Developer Tools, Move Tools, Disk Map, Large Files.
- **W4:** Uninstaller.
- **W5:** tray icon, low-space alerts, scheduled clean, Recycle Bin.
- **Ship:** icons, Store listing, redacted screenshots, README section, `winget` check.
- **W6, W7:** elevated helper, Disk Digger.

## Status (2026-11-25, written, never compiled)
- **Written:** W1 to W7, the Store listing (`docs/WINDOWS_STORE.md`) and the README section.
- **Left for the owner:** build and test on the PC, screenshots, Partner Center, publisher identity, submission.
- **Differs from the plans:**
  - Disk Map shows one "Not visible to this scan" block instead of per-volume rows, and has no "scan with admin rights": the elevated helper takes no paths.
  - A folder holding any git repository is Critical; unpushed work is not checked, so no `git` runs on unknown repos.
  - The database tool signs in as `root` on 127.0.0.1:3306 and ignores option files; a password has to be saved with `mysql_config_editor`.
- **Elevated helper:** `devduster-helper.exe` (`Windows/DevDuster.Helper`), NativeAOT so user environment variables can't load code into it. It takes one task id (`update-cache`, `component-cleanup`, `dumps`), starts with a UAC prompt from the package folder and needs `allowElevation`. The app build publishes it into the package.

## First run on the Windows PC
1. `dotnet test Windows/DevDuster.Core.Tests`. A command-line app build (`dotnet build Windows/DevDuster.App -p:Platform=x64`) needs `%ProgramFiles(x86)%\Microsoft Visual Studio\Installer` on PATH, or the helper link fails with "vswhere.exe is not recognized".
2. `dotnet run --project Windows/DevDuster.Cli -- scan` is read-only. Compare its paths with Explorer.
3. Try a clean in a throwaway account or VM before your own profile.
4. Open `Windows/DevDuster.slnx`, set `DevDuster.App` as startup, platform x64, run.
5. Check deletes by hand: a junction inside a target, a file open in another app, an item larger than the Recycle Bin limit, a USB drive.
6. Move Tools: move a small tool, undo it, then kill the app mid-copy and relaunch.
7. System page: confirm `devduster-helper.exe` is in the package, the UAC prompt appears and each task works from the installed package.
8. Tray: close the window, check the icon, "Scan now", "Quit", and that a second launch shows the same window.
9. Uninstaller > Leftover folders and Disk Map > Databases: check the list against what you know before removing anything.

## Store risk
Packaged apps get `AppData` writes virtualized, so a delete could miss the real file. The manifest turns that off with `desktop6:FileSystemWriteVirtualization` and the restricted capabilities `unvirtualizedResources` and `runFullTrust`. Store review needs a written reason ("developer cache cleaner that removes files the user picks"). Confirm on the PC that a delete in `%LOCALAPPDATA%` is real. Fallback: an unpackaged installer on winget and GitHub, signed with Azure Artifact Signing.
