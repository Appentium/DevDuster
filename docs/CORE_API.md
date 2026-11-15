# SweepCore API

Everything the app, CLI and helper need from `import SweepCore`. All types are `Sendable`; the
long calls are `async` and run off the main actor, so call them from a `Task` in a view model.

## Rules

| Type | What it is |
|---|---|
| `Tier` | `.safe`, `.review`, `.caution` |
| `Rule` | `id`, `title`, `tier`, `target`, `regenerate` (show it next to the item), `pick`, `excluding`, `minAgeDays`, `processGuard`, `skipsRunningApps` |
| `Rule.Target` | `.home([glob])` relative to home, `.project(directory:markers:)`, or `.dockerPrune` |
| `RuleCatalog(home:)` | The built-in rules in precedence order. `home` defaults to the real home; tests pass a temp dir |
| `ProjectArtifactMatcher(catalog:)` | `rule(forArtifact: url) -> Rule?`: the project rule for a folder, only when its marker file sits next to it |

## Scanning

| Call | Returns |
|---|---|
| `SweepScanner(catalog:volumes:processes:)` | `volumes` and `processes` default to the real machine |
| `ProcessProbe(isRunning:runningApps:)` | `.system` reads `ps` and `NSWorkspace`; tests inject fixed answers. `RunningApp` is `bundleIdentifier` + `name` |
| `scanner.scan(_ options) -> AsyncStream<ScanEvent>` | `.progress(ScanPhase, path:)`, `.item(ScanItem)` as each is measured, then `.finished(ScanReport)`. Cancelling the consuming task stops the scan |
| `await scanner.run(_ options) -> ScanReport` | Same scan, final report only |
| `ScanOptions(staleDays: 14, excludedPaths: [], tiers: all, scope: nil)` | `scope` limits the scan to items inside those folders; `nil` means home plus every writable local volume. `isStale(date)` applies `staleDays` |
| `ScanItem` | `rule`, `url` (real path), `bytes` (allocated, hard links counted once per scan), `id` |
| `ScanReport` | `items` (catalog order, then largest first), `skipped: [SkippedRule]` (rule + the running process that blocked it), `skippedItems: [SkippedItem]`, `totalBytes` (offered items only) |
| `SkippedItem` | `item` (measured) + `runningApp`, for an item whose app is open: show "Quit \(runningApp) to clean \(bytes)". Applies to rules with `skipsRunningApps` (User caches, User logs, Electron app caches) |
| `FlutterProjectScanner(catalog:volumes:)` | `await scan(_ options) -> [FlutterProject]`: every `pubspec.yaml` with `sdk: flutter`, stale or not |
| `FlutterProject` | `url`, `lastActivity`, `folders: [ScanItem]` (present `.dart_tool`, `build`, `ios/Pods`, `ios/.symlinks`, `android/.gradle`), `totalBytes`. Use `options.isStale(project.lastActivity)` for "Select stale" |
| `SizeCalculator()` | `allocatedSize(of: url) -> Int64`; one instance dedupes hard links across all its calls |

## Cleaning

| Call | Returns |
|---|---|
| `Cleaner(catalog:log:)` | `log` defaults to `~/Library/Logs/Sweep/clean.log` |
| `await cleaner.clean(items:mode:) -> [CleanResult]` | `mode` is `.trash` (default) or `.delete`. Only pass `ScanItem`s from a scan |
| `CleanResult` | `item`, `error: CleanError?` (`nil` = removed), `trashedURL` (where it went, for Restore) |
| `CleanError` | `.refused(DenyGuard.Refusal)`, `.dockerNotRunning`, `.failed(message)` |
| `DenyGuard(catalog:)` | `check(url, rule:) throws(Refusal) -> URL`. `Cleaner` already calls it on every item |
| `CleanLog(url:)` / `CleanLog(home:)` | One line per removed item: `ISO-8601 time<TAB>mode<TAB>bytes<TAB>path` |

The Docker item (`rule.target == .dockerPrune`) is never deleted as files: cleaning it runs
`docker system prune -f`, and only while Docker is running. Its size is an estimate.

## Volumes

| Call | Returns |
|---|---|
| `VolumeService(home:)` | `volumes() -> [Volume]` (local, mounted, browsable) |
| `Volume` | `url`, `name`, `format` (`apfs`, `ntfs`…), `totalBytes`, `availableBytes`, `importantAvailableBytes`, `isInternal`, `isBoot`, `isReadOnly`, `trashURL` (`~/.Trash` on the boot disk, `.Trashes/<uid>` elsewhere) |
| `trashSize(of:) -> Int64`, `emptyTrash(of:) throws` | Trashing on an external volume frees nothing until its trash is emptied. Emptying is permanent, so confirm first |

## Example

```swift
import SweepCore

@MainActor @Observable final class CleanerModel {
    private let catalog = RuleCatalog()
    var items: [ScanItem] = []
    var scanning = false

    func scan(tiers: Set<Tier>) async {
        scanning = true
        items = []
        for await event in SweepScanner(catalog: catalog).scan(ScanOptions(tiers: tiers)) {
            switch event {
            case .item(let item): items.append(item)
            case .finished(let report): items = report.items
            case .progress: break
            }
        }
        scanning = false
    }

    func clean(_ selected: [ScanItem], moveToTrash: Bool) async -> [CleanResult] {
        await Cleaner(catalog: catalog).clean(items: selected, mode: moveToTrash ? .trash : .delete)
    }
}
```
