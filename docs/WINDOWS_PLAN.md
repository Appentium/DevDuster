# DevDuster for Windows: plan

## Decisions
- **Stack:** C# on .NET 10 (LTS), WinUI 3 (Windows App SDK), MVVM with CommunityToolkit.Mvvm, tests with xUnit.
- **Repo:** this repo, new `Windows/` folder. The Mac app stays untouched.
- **Rules:** ported to a C# catalog with Windows paths. They aren't shared with the Swift catalog, because almost every path differs.
- **Publisher:** Appentium LLC Microsoft Store account. Reserve the name "DevDuster" first.
- **Shipping:** an MSIX package through the Microsoft Store. The Store signs it, so no code signing certificate is needed. winget installs it from the Store source (`winget install DevDuster`), so one package covers both.
- **Delete:** Recycle Bin by default, with permanent delete as an opt-in, same as the Mac app.
- **Targets:** Windows 10 22H2+ and Windows 11, x64 and ARM64.

## Layout
```
Windows/
  DevDuster.sln
  DevDuster.Core/        net10.0, pure logic, builds and tests on the Mac too
    Rules/   Rule, RuleCatalog, ProjectArtifactMatcher
    Scan/    Scanner, SizeCalculator
    Clean/   Cleaner (through an IFileRemover interface), DenyGuard, CleanLog
  DevDuster.Platform/    net10.0-windows: RecycleBinRemover (IFileOperation), DriveService, known folders
  DevDuster.App/         WinUI 3 app, MSIX packaged
  DevDuster.Cli/         duster.exe (scan, clean, --json)
  DevDuster.Core.Tests/
```
Keeping Core free of Windows APIs means agents on the Mac can run `dotnet test` without a Windows VM. Only the App and Platform projects need Windows.

## Safety rules (Core)
- Never follow junctions, symlinks or other reparse points. Windows dev setups use them a lot, and following one can delete the real target.
- Size is allocated size (`GetCompressedFileSizeW`), and hard links are counted once.
- DenyGuard blocks `C:\Windows`, `Program Files`, the user profile root, drive roots and anything outside a rule's allowlisted root.
- Skip locked files and report them. Never retry them in a loop.

## Windows rule catalog (v1)
| Group | Paths |
|---|---|
| Gradle | `%USERPROFILE%\.gradle\caches`, `wrapper\dists` (old versions), `daemon` |
| Android | `%LOCALAPPDATA%\Android\Sdk` (old system-images, NDKs, build-tools), `%USERPROFILE%\.android\avd` (pick each) |
| Flutter / Dart | `%LOCALAPPDATA%\Pub\Cache` |
| JS | `%LOCALAPPDATA%\npm-cache`, Yarn and pnpm stores |
| .NET | `%USERPROFILE%\.nuget\packages`, `%LOCALAPPDATA%\NuGet\v3-cache` |
| Python | `%LOCALAPPDATA%\pip\Cache` |
| IDEs | JetBrains and VS Code caches and logs, Visual Studio `ComponentModelCache` |
| Temp and crash | `%TEMP%`, `%LOCALAPPDATA%\CrashDumps` |
| Projects | `build`, `.dart_tool`, `node_modules`, `bin`/`obj`, `.gradle` next to their marker files |
| Recycle Bin | size and empty per drive |

## Phases
**W0: setup (owner, ~1 hour)**
- Parallels + Windows 11 ARM on the Mac.
- Visual Studio 2026 Community with the .NET desktop and WinUI workloads.
- `brew install dotnet` on the Mac.
- Reserve "DevDuster" in Partner Center.

**W1: Core + CLI.** Rule model, catalog, scanner, size, DenyGuard, cleaner, project matcher, tests. `duster scan` and `duster clean` work from a terminal.

**W2: app.** NavigationView shell, Cleaner and Projects screens, a confirm dialog with sizes, settings, clean log.

**W3: disk tools.** Large and old file finder, disk map (treemap), drive overview.

**W4: ship.**
- MSIX manifest, icons, Store listing and redacted screenshots.
- Submit to the Store, then check that `winget install` works.
- Add a Windows section to the README.

**v2 (later):**
- Admin cleanup through an elevated helper: Windows Update cache, DISM component cleanup.
- Compact the Docker/WSL `.vhdx`.
- Scheduled Safe clean through Task Scheduler.
- Tray icon and low-space alerts.
- Uninstaller.

## Store risk to check in W0
Packaged desktop apps get their writes to `AppData` virtualized, so a delete could miss the real files. The app needs the restricted capability `unvirtualizedResources` with `desktop6:FileSystemWriteVirtualization` disabled, plus `runFullTrust`. Restricted capabilities need a written reason at Store review ("developer cache cleaner that removes files the user picks"). Build a tiny test package in W0 that deletes a file in `%LOCALAPPDATA%` and confirm it is really gone before W1 starts.

Fallback if the Store refuses it: ship an unpackaged installer through winget and GitHub, signed with Azure Artifact Signing (about $10 a month).

## Workers
- **W1 Core:** Antigravity `gemini-4-hydrogen-high`. The brief carries exact signatures and test cases. Cleaner, DenyGuard and the reparse-point logic get an Opus review because they delete files.
- **W2 and W3 UI:** a Sonnet side session. It needs the Windows VM to build, so the owner runs builds or a Windows-capable session does.
- **W4 listing text and README:** a free opencode model.
