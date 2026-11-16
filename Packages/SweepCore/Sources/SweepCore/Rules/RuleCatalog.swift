import Foundation

public struct RuleCatalog: Sendable {
    public let home: URL
    public let rules: [Rule]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, developerOnly: Bool = false) {
        self.home = home
        rules = developerOnly ? Self.builtIn.filter { $0.platform != nil } : Self.builtIn
    }

    public var projectRules: [Rule] {
        rules.filter {
            if case .project = $0.target { return true }
            return false
        }
    }

    public static let userSelected = Rule(
        id: "user.selected", title: "Selected by user", tier: .review,
        target: .userSelected,
        regenerate: "Chosen by you in Disk Map or Large Files; not regenerated."
    )

    private static let builtIn: [Rule] = [
        // Order is precedence: earlier rules claim paths first, so specific rules precede the broad globs.
        Rule(
            id: "xcode.derived-data", title: "Xcode DerivedData", tier: .safe, platform: .apple,
            target: .home(["Library/Developer/Xcode/DerivedData/*"]),
            regenerate: "Xcode rebuilds it on the next build."
        ),
        Rule(
            id: "simulator.caches", title: "CoreSimulator caches", tier: .safe, platform: .apple,
            target: .home(["Library/Developer/CoreSimulator/Caches/*"]),
            regenerate: "Simulators rebuild their caches on next boot."
        ),
        Rule(
            id: "simulator.temp", title: "CoreSimulator temp files", tier: .safe, platform: .apple,
            target: .home(["Library/Developer/CoreSimulator/Temp/*"]),
            regenerate: "Simulators write new temp files as they run."
        ),
        Rule(
            id: "xcode.previews", title: "SwiftUI preview data", tier: .safe, platform: .apple,
            target: .home(["Library/Developer/Xcode/UserData/Previews/*"]),
            regenerate: "Xcode rebuilds previews the next time a canvas opens."
        ),
        Rule(
            id: "xcode.ib-support", title: "Interface Builder support files", tier: .safe, platform: .apple,
            target: .home(["Library/Developer/Xcode/UserData/IB Support/*", "Library/Developer/Xcode/UserData/IB%20Support/*"]),
            regenerate: "Xcode recreates them when a storyboard or XIB opens."
        ),
        Rule(
            id: "xcode.documentation-cache", title: "Xcode documentation cache", tier: .safe, platform: .apple,
            target: .home(["Library/Developer/Xcode/DocumentationCache/*"]),
            regenerate: "Xcode rebuilds it when documentation is opened."
        ),
        Rule(
            id: "swiftpm.cache", title: "Swift Package Manager cache", tier: .safe, platform: .apple,
            target: .home(["Library/Caches/org.swift.swiftpm"]),
            regenerate: "Package resolution downloads packages again."
        ),
        Rule(
            id: "android.sdk-cache", title: "Android SDK Manager cache", tier: .safe, platform: .android,
            target: .home([".android/cache"]),
            regenerate: "The SDK Manager downloads its package lists again."
        ),
        Rule(
            id: "gradle.daemon", title: "Gradle daemon logs", tier: .safe, platform: .android,
            target: .home([".gradle/daemon/*"]),
            regenerate: "Gradle recreates it when a daemon starts.",
            processGuard: [gradleDaemon]
        ),
        Rule(
            id: "gradle.build-cache", title: "Gradle build cache", tier: .safe, platform: .android,
            target: .home([".gradle/caches/build-cache-*"]),
            regenerate: "Gradle refills it on the next build.",
            processGuard: [gradleDaemon]
        ),
        Rule(
            id: "homebrew.cache", title: "Homebrew cache", tier: .safe,
            target: .home(["Library/Caches/Homebrew"]),
            regenerate: "Homebrew downloads bottles again when needed."
        ),
        Rule(
            id: "cocoapods.cache", title: "CocoaPods cache", tier: .safe, platform: .apple,
            target: .home(["Library/Caches/CocoaPods"]),
            regenerate: "pod install downloads specs and pods again."
        ),
        Rule(
            id: "pip.cache", title: "pip cache", tier: .safe,
            target: .home(["Library/Caches/pip"]),
            regenerate: "pip downloads wheels again when needed."
        ),
        Rule(
            id: "yarn.cache", title: "Yarn cache", tier: .safe,
            target: .home(["Library/Caches/Yarn"]),
            regenerate: "yarn install downloads packages again."
        ),
        Rule(
            id: "npm.cache", title: "npm cache", tier: .safe,
            target: .home([".npm/_cacache"]),
            regenerate: "npm install downloads packages again."
        ),
        Rule(
            id: "electron.caches", title: "Electron app caches", tier: .safe,
            target: .home([
                "Library/Application Support/*/Cache",
                "Library/Application Support/*/Code Cache",
                "Library/Application Support/*/GPUCache",
            ]),
            regenerate: "Each app rebuilds its web cache on launch.",
            skipsRunningApps: true
        ),
        Rule(
            id: "android-studio.old", title: "Old Android Studio caches and logs", tier: .review, platform: .android,
            target: .home(["Library/Caches/Google/AndroidStudio*", "Library/Logs/Google/AndroidStudio*"]),
            regenerate: "Only versions older than the newest install; they are never read again.",
            pick: .allButNewestVersion
        ),
        Rule(
            id: "logs", title: "User logs", tier: .safe,
            target: .home(["Library/Logs/*"]),
            regenerate: "Apps write new logs as they run.",
            excluding: ["Library/Logs/Sweep"],
            skipsRunningApps: true
        ),
        Rule(
            id: "caches", title: "User caches", tier: .safe,
            target: .home(["Library/Caches/*"]),
            regenerate: "Apps rebuild their caches as they run.",
            skipsRunningApps: true
        ),
        Rule(
            id: "gradle.caches", title: "Old Gradle caches", tier: .review, platform: .android,
            target: .home([".gradle/caches/[0-9]*"]),
            regenerate: "Only versions older than the newest; Gradle re-downloads if an old one is used.",
            pick: .allButNewestVersion,
            processGuard: [gradleDaemon]
        ),
        Rule(
            id: "gradle.wrapper", title: "Old Gradle wrapper distributions", tier: .review, platform: .android,
            target: .home([".gradle/wrapper/dists/*"]),
            regenerate: "The wrapper downloads a version again when a project asks for it.",
            pick: .allButNewestVersion,
            processGuard: [gradleDaemon]
        ),
        Rule(
            id: "xcode.device-support", title: "Old iOS DeviceSupport", tier: .review, platform: .apple,
            target: .home(["Library/Developer/Xcode/iOS DeviceSupport/*"]),
            regenerate: "Xcode copies symbols again when that iOS version is connected.",
            pick: .allButNewestVersion
        ),
        Rule(
            id: "simulator.unavailable", title: "Unavailable simulators", tier: .review, platform: .apple,
            target: .simulatorDevices,
            regenerate: "Runs xcrun simctl delete unavailable: simulators whose iOS version is no longer installed."
        ),
        Rule(
            id: "xcode.device-logs", title: "Device logs copied by Xcode", tier: .review, platform: .apple,
            target: .home(["Library/Developer/Xcode/DeviceLogs/*"]),
            regenerate: "Xcode copies logs again the next time a device connects."
        ),
        Rule(
            id: "pub.cache", title: "Dart pub cache", tier: .review,
            target: .home([".pub-cache/hosted", ".pub-cache/git", ".pub-cache/_temp"]),
            regenerate: "flutter pub get downloads packages again; globally activated tools are kept."
        ),
        Rule(
            id: "docker.prune", title: "Docker unused data (estimate)", tier: .review,
            target: .dockerPrune,
            regenerate: "Runs docker system prune -f: stopped containers, unused networks, dangling images and build cache."
        ),
        Rule(
            id: "android.avds", title: "Android emulators (AVDs)", tier: .caution, platform: .android,
            target: .home([".android/avd/*.avd"]),
            regenerate: "Recreate in Device Manager; the emulator's data is lost."
        ),
        Rule(
            id: "android.system-images", title: "Unused Android system images", tier: .caution, platform: .android,
            target: .home(["Library/Android/sdk/system-images/*/*/*"]),
            regenerate: "Images no AVD uses; the SDK Manager downloads them again.",
            pick: .unreferencedByAVDs
        ),
        Rule(
            id: "android.ndk", title: "Old Android NDKs", tier: .caution, platform: .android,
            target: .home(["Library/Android/sdk/ndk/*"]),
            regenerate: "Only versions older than the newest; the SDK Manager downloads them again.",
            pick: .allButNewestVersion
        ),
        Rule(
            id: "simulator.runtimes", title: "Old simulator runtimes", tier: .caution, platform: .apple,
            target: .simulatorRuntimes,
            regenerate: "Only versions older than the newest per platform; Xcode downloads one again from Settings → Components."
        ),
        Rule(
            id: "android.build-tools", title: "Old Android build tools", tier: .caution, platform: .android,
            target: .home(["Library/Android/sdk/build-tools/*"]),
            regenerate: "Only versions older than the newest; Gradle downloads a version again if a project pins it.",
            pick: .allButNewestVersion
        ),
        Rule(
            id: "android.platforms", title: "Old Android SDK platforms", tier: .caution, platform: .android,
            target: .home(["Library/Android/sdk/platforms/*"]),
            regenerate: "Only versions older than the newest; Gradle downloads one again if a project compiles against it.",
            pick: .allButNewestVersion
        ),
        Rule(
            id: "xcode.archives", title: "Xcode archives", tier: .caution, platform: .apple,
            target: .home(["Library/Developer/Xcode/Archives/*"]),
            regenerate: "Not regenerable: needed to symbolicate crashes of shipped builds.",
            minAgeDays: 90
        ),
        Rule(
            id: "ios.backups", title: "iPhone and iPad backups", tier: .caution,
            target: .home(["Library/Application Support/MobileSync/Backup/*"]),
            regenerate: "Not regenerable: back up the device again first."
        ),
        Rule(
            id: "project.flutter-build", title: "Flutter build output", tier: .review,
            target: .project(directory: "build", markers: ["pubspec.yaml"]),
            regenerate: "flutter build recreates it."
        ),
        Rule(
            id: "project.dart-tool", title: "Dart tool folders", tier: .review,
            target: .project(directory: ".dart_tool", markers: ["pubspec.yaml"]),
            regenerate: "flutter pub get recreates it."
        ),
        Rule(
            id: "project.gradle-build", title: "Gradle build output", tier: .review,
            target: .project(directory: "build", markers: ["build.gradle", "build.gradle.kts"]),
            regenerate: "The next Gradle build recreates it."
        ),
        Rule(
            id: "project.gradle", title: "Gradle project caches", tier: .review,
            target: .project(directory: ".gradle", markers: ["build.gradle", "build.gradle.kts"]),
            regenerate: "The next Gradle build recreates it."
        ),
        Rule(
            id: "project.pods", title: "CocoaPods Pods", tier: .review,
            target: .project(directory: "Pods", markers: ["Podfile"]),
            regenerate: "pod install recreates it."
        ),
        Rule(
            id: "project.ios-symlinks", title: "Flutter iOS plugin links", tier: .review,
            target: .project(directory: ".symlinks", markers: ["Podfile"]),
            regenerate: "flutter pub get recreates it."
        ),
        Rule(
            id: "project.node-modules", title: "node_modules", tier: .review,
            target: .project(directory: "node_modules", markers: ["package.json"]),
            regenerate: "npm, yarn or pnpm install recreates it."
        ),
        Rule(
            id: "project.cargo-target", title: "Cargo target", tier: .review,
            target: .project(directory: "target", markers: ["Cargo.toml"]),
            regenerate: "cargo build recreates it."
        ),
    ]

    private static let gradleDaemon = "GradleDaemon"
}
