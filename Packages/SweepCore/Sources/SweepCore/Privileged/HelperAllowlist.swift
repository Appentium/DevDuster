import Foundation

public enum HelperAllowlist {
    static let archiveMinimumAge: TimeInterval = 86_400
    private static let applicationFolders: Set<String> = ["/Applications", "/Applications/Utilities"]
    private static let nestedAppRoots = ["/Applications/", "/Library/Application Support/"]
    private static let systemUninstallFolders: Set<String> = [
        "/Library/Application Support", "/Library/Caches", "/Library/Preferences", "/Library/Logs", "/Library/LaunchAgents",
        "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools", "/Library/Internet Plug-Ins", "/Library/QuickLook",
        "/Library/Spotlight", "/Library/PreferencePanes", "/Library/Screen Savers", "/Library/Input Methods",
        "/Library/Audio/Plug-Ins/HAL", "/Library/Audio/Plug-Ins/Components", "/private/var/db/receipts",
    ]
    private static let userUninstallFolders: Set<String> = [
        "Application Support", "Caches", "Preferences", "Logs", "LaunchAgents", "Containers", "Group Containers",
        "HTTPStorages", "WebKit", "Saved Application State",
    ]
    static let aslMinimumAge: TimeInterval = 7 * 86_400

    public static func isSnapshotDate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.map(\.count) == [4, 2, 2, 6], parts.allSatisfy(isASCIIDigits) else { return false }
        let time = parts[3]
        let numbers = [parts[0], parts[1], parts[2], time.prefix(2), time.dropFirst(2).prefix(2), time.suffix(2)].compactMap { Int($0) }
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian), timeZone: .gmt,
            year: numbers[0], month: numbers[1], day: numbers[2], hour: numbers[3], minute: numbers[4], second: numbers[5]
        )
        return components.isValidDate
    }

    public static func isSingleComponent(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains("\0") && name.utf8.count <= 255
    }

    public static func isSystemCacheName(_ name: String) -> Bool {
        // APFS is case-insensitive, so "COM.APPLE.x" names the same folder as "com.apple.x".
        isSingleComponent(name) && !name.lowercased().hasPrefix("com.apple.")
    }

    public static func isCleanableCache(_ name: String, reported: [String]) -> Bool {
        isSystemCacheName(name) && reported.contains(name)
    }

    public static func isArchivedLog(_ relativePath: String, modified: Date, now: Date) -> Bool {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let name = components.last, components.allSatisfy(isSingleComponent) else { return false }
        let age = now.timeIntervalSince(modified)
        if components == ["asl", name], name.hasSuffix(".asl") { return age >= aslMinimumAge }
        // A file touched in the last day may still be mid-rotation or mid-compression.
        guard age >= archiveMinimumAge else { return false }
        if name.hasSuffix(".gz") || name.hasSuffix(".bz2") { return true }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1, let base = parts.first, let suffix = parts.last else { return false }
        return !base.isEmpty && !isASCIIDigits(base) && isASCIIDigits(suffix)
    }

    public static func isUninstallPath(_ path: String) -> Bool {
        let url = URL(filePath: path)
        let name = url.lastPathComponent
        let parent = url.deletingLastPathComponent().filePath
        let lowered = name.lowercased()
        guard path.hasPrefix("/"), url.standardized.filePath == path, isSingleComponent(name),
              !lowered.hasPrefix("com.apple."), !lowered.contains("com.appentium.sweep"), lowered != "sweep.app" else { return false }
        if applicationFolders.contains(parent) { return name.hasSuffix(".app") }
        if isNestedApp(path) { return true }
        if systemUninstallFolders.contains(parent) { return true }
        let components = parent.split(separator: "/").map(String.init)
        guard components.count >= 4, components[0] == "Users", isSingleComponent(components[1]), components[2] == "Library" else { return false }
        return userUninstallFolders.contains(components.dropFirst(3).joined(separator: "/"))
    }

    static func isNestedApp(_ path: String) -> Bool {
        // Hidden helper apps sit deep inside vendor folders, so only an app bundle may be that far down.
        path.hasSuffix(".app") && nestedAppRoots.contains(where: path.hasPrefix)
            && path.split(separator: "/").allSatisfy { isSingleComponent(String($0)) }
    }

    public static func isTrashVolume(_ name: String, mounted: [String]) -> Bool {
        isSingleComponent(name) && mounted.contains(name)
    }

    private static func isASCIIDigits(_ text: Substring) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
    }
}
