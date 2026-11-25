# DevDuster for Windows — Store listing

Draft. The app is not yet published. DevDuster is an Appentium project: https://appentium.com.

## Name and descriptions

**Name:** DevDuster

**Short description:** Developer cache cleaner, project analyzer, and disk manager.

**Long description:** DevDuster finds developer caches, logs and build output on Windows and lets you remove what you choose. It uses built-in rules for tool data (Android and Gradle, JavaScript, Python, Rust, Go, JVM, PHP, Ruby, .NET, editors, AI tools, game engines and DevOps tools) and for project folders such as `node_modules` and `build`.

Items are grouped as Safe (rebuilt automatically), Review (downloaded or rebuilt on demand) and Caution (you pick each item; not regenerable offline). Rules skip while their tool is running, and a guard refuses system and personal folders. Deletes go to the Recycle Bin by default; permanent delete is opt-in. Every removal is logged to `%LOCALAPPDATA%\DevDuster\Logs\clean.log`.

Requires Windows 10 22H2 or later, or Windows 11, on x64 or ARM64.

## Features

- Built-in rules for caches, logs and build output across the tool families listed above.
- Three tiers: Safe, Review and Caution.
- Project rules only claim a folder when its marker file is present, for example `node_modules` next to `package.json`.
- Rules skip while their tool is running; a guard refuses drive roots, system folders and personal folders.
- Recycle Bin by default, permanent delete opt-in, and a log of every removal.
- CLI through the packaged `duster.exe` alias: `scan` (read-only, with `--json` and `--tier`) and `clean` (with `--delete` and `--yes`).
- App sections for Cleaner, Projects, Developer Tools, Move Tools, Disk Map, Large Files, Uninstaller, System, Dashboard and Settings.

**Category:** Developer Tools

**Keywords:** developer tools, cache cleaner, build output, disk space, node_modules, Gradle, npm, NuGet, pip, Cargo, projects

## Privacy statement

DevDuster collects no data and sends nothing. Scanning and cleaning run locally on your PC. There are no network calls in the Windows source: a search of the C# files for network APIs (`HttpClient`, `WebRequest`, `WebClient`, sockets, DNS and similar) found none. The only `http` strings in the repository are XML/XAML namespace declarations in manifest and XAML files; they are identifiers, not requests. There are no accounts, telemetry or analytics. The Microsoft Store handles installation and updates.

## Restricted capabilities

The manifest disables file-system write virtualization (`desktop6:FileSystemWriteVirtualization`) and requests three restricted capabilities. Written reason for Store review: DevDuster is a developer cache cleaner that removes files the user picks. Packaged apps normally get `AppData` writes virtualized, so a delete could miss the real file. These settings let the app delete the actual files the user selects in `%LOCALAPPDATA%`.

- `unvirtualizedResources`: needed with write virtualization disabled, so a delete in `%LOCALAPPDATA%` affects the real file instead of a per-app virtual copy.
- `runFullTrust`: needed to read and remove developer files across the user profile and to expose the packaged `duster.exe` console execution alias (`Windows.FullTrustApplication`).
- `allowElevation`: needed for the System section. After a UAC prompt, the packaged native `devduster-helper.exe` runs one of three fixed tasks (Windows Update downloads, DISM component cleanup, crash dumps). It takes no paths from the caller.

Confirm on the Windows PC that a delete in `%LOCALAPPDATA%` is real. If review rejects this, the fallback is an unpackaged installer on winget and GitHub, signed with Azure Artifact Signing.

## winget

After the app is published in the Microsoft Store, it is installable with winget through the `msstore` source. No separate winget package is needed. Check the Store ID and the install command on the PC after publishing.

## Owner checklist

- [ ] Reserve the name "DevDuster" in Partner Center.
- [ ] Set the publisher identity in `Windows/DevDuster.App/Package.appxmanifest` to match the Store account (`Identity Name` and `Publisher`), and keep the version in step with the release. Current values: `Appentium.DevDuster`, `CN=Appentium LLC`, `0.1.0.0`.
- [ ] Build and test on the Windows PC; the source has never been compiled. Check a real delete in `%LOCALAPPDATA%`.
- [ ] Take Store screenshots and redact personal data: paths, project names and account names.
- [ ] Submit the package with the written capability justification.
