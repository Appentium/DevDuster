import Foundation

public struct RuleCatalog: Sendable {
    public let home: URL
    public let rules: [Rule]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        rules = Self.builtIn
    }

    public var projectRules: [Rule] {
        rules.filter {
            if case .project = $0.target { return true }
            return false
        }
    }

    private static let builtIn: [Rule] = [
        // Order is precedence: earlier rules claim paths first, so specific rules precede the broad globs.
        Rule(
            id: "xcode.derived-data", title: "Xcode DerivedData", tier: .safe,
            target: .home(["Library/Developer/Xcode/DerivedData/*"]),
            regenerate: "Xcode rebuilds it on the next build."
        ),
        Rule(
            id: "simulator.caches", title: "CoreSimulator caches", tier: .safe,
            target: .home(["Library/Developer/CoreSimulator/Caches/*"]),
            regenerate: "Simulators rebuild their caches on next boot."
        ),
        Rule(
            id: "gradle.daemon", title: "Gradle daemon logs", tier: .safe,
            target: .home([".gradle/daemon/*"]),
            regenerate: "Gradle recreates it when a daemon starts.",
            processGuard: [gradleDaemon]
        ),
        Rule(
            id: "gradle.build-cache", title: "Gradle build cache", tier: .safe,
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
            id: "cocoapods.cache", title: "CocoaPods cache", tier: .safe,
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
            regenerate: "Each app rebuilds its web cache on launch."
        ),
        Rule(
            id: "android-studio.old", title: "Old Android Studio caches and logs", tier: .review,
            target: .home(["Library/Caches/Google/AndroidStudio*", "Library/Logs/Google/AndroidStudio*"]),
            regenerate: "Only versions older than the newest install; they are never read again.",
            pick: .allButNewestVersion
        ),
        Rule(
            id: "logs", title: "User logs", tier: .safe,
            target: .home(["Library/Logs/*"]),
            regenerate: "Apps write new logs as they run.",
            excluding: ["Library/Logs/Sweep"]
        ),
        Rule(
            id: "caches", title: "User caches", tier: .safe,
            target: .home(["Library/Caches/*"]),
            regenerate: "Apps rebuild their caches as they run."
        ),
        Rule(
            id: "gradle.caches", title: "Old Gradle caches", tier: .review,
            target: .home([".gradle/caches/[0-9]*"]),
            regenerate: "Only versions older than the newest; Gradle re-downloads if an old one is used.",
            pick: .allButNewestVersion,
            processGuard: [gradleDaemon]
        ),
        Rule(
            id: "gradle.wrapper", title: "Old Gradle wrapper distributions", tier: .review,
            target: .home([".gradle/wrapper/dists/*"]),
            regenerate: "The wrapper downloads a version again when a project asks for it.",
            pick: .allButNewestVersion,
            processGuard: [gradleDaemon]
        ),
        Rule(
            id: "xcode.device-support", title: "Old iOS DeviceSupport", tier: .review,
            target: .home(["Library/Developer/Xcode/iOS DeviceSupport/*"]),
            regenerate: "Xcode copies symbols again when that iOS version is connected.",
            pick: .allButNewestVersion
        ),
        Rule(
            id: "pub.cache", title: "Dart pub cache", tier: .review,
            target: .home([".pub-cache/*"]),
            regenerate: "flutter pub get downloads packages again; global tools need re-activating."
        ),
        Rule(
            id: "docker.prune", title: "Docker unused data (estimate)", tier: .review,
            target: .dockerPrune,
            regenerate: "Runs docker system prune -f: stopped containers, unused networks, dangling images and build cache."
        ),
        Rule(
            id: "android.avds", title: "Android emulators (AVDs)", tier: .caution,
            target: .home([".android/avd/*.avd"]),
            regenerate: "Recreate in Device Manager; the emulator's data is lost."
        ),
        Rule(
            id: "android.system-images", title: "Unused Android system images", tier: .caution,
            target: .home(["Library/Android/sdk/system-images/*/*/*"]),
            regenerate: "Images no AVD uses; the SDK Manager downloads them again.",
            pick: .unreferencedByAVDs
        ),
        Rule(
            id: "android.ndk", title: "Old Android NDKs", tier: .caution,
            target: .home(["Library/Android/sdk/ndk/*"]),
            regenerate: "Only versions older than the newest; the SDK Manager downloads them again.",
            pick: .allButNewestVersion
        ),
        Rule(
            id: "xcode.archives", title: "Xcode archives", tier: .caution,
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
