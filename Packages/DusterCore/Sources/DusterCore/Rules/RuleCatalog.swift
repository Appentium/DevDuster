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
            id: "homebrew.cache", title: "Homebrew cache", tier: .safe, platform: .devTools,
            target: .home(["Library/Caches/Homebrew"]),
            regenerate: "Homebrew downloads bottles again when needed."
        ),
        Rule(
            id: "cocoapods.cache", title: "CocoaPods cache", tier: .safe, platform: .apple,
            target: .home(["Library/Caches/CocoaPods"]),
            regenerate: "pod install downloads specs and pods again."
        ),
        Rule(
            id: "pip.cache", title: "pip cache", tier: .safe, platform: .python,
            target: .home(["Library/Caches/pip"]),
            regenerate: "pip downloads wheels again when needed."
        ),
        Rule(
            id: "yarn.cache", title: "Yarn cache", tier: .safe, platform: .javascript,
            target: .home(["Library/Caches/Yarn", ".yarn/berry/cache"]),
            regenerate: "yarn install downloads packages again."
        ),
        Rule(
            id: "npm.cache", title: "npm cache", tier: .safe, platform: .javascript,
            target: .home([".npm/_cacache", ".npm/_npx"]),
            regenerate: "npm install downloads packages again."
        ),
        Rule(
            id: "pnpm.store", title: "pnpm store", tier: .safe, platform: .javascript,
            target: .home(["Library/pnpm/store"]),
            regenerate: "pnpm install downloads packages again; existing node_modules keep working."
        ),
        Rule(
            id: "bun.cache", title: "Bun cache", tier: .safe, platform: .javascript,
            target: .home([".bun/install/cache"]),
            regenerate: "bun install downloads packages again."
        ),
        Rule(
            id: "deno.cache", title: "Deno cache", tier: .safe, platform: .javascript,
            target: .home(["Library/Caches/deno"]),
            regenerate: "Deno downloads modules again on the next run."
        ),
        Rule(
            id: "node.tooling-caches", title: "Node tooling caches", tier: .safe, platform: .javascript,
            target: .home([
                "Library/Caches/node-gyp",
                "Library/Caches/typescript",
                "Library/Caches/electron",
                "Library/Caches/electron-builder",
            ]),
            regenerate: "Each tool downloads what it needs again."
        ),
        Rule(
            id: "browsers.testing", title: "Playwright and Puppeteer browsers", tier: .review, platform: .javascript,
            target: .home(["Library/Caches/ms-playwright/*", ".cache/puppeteer/*"]),
            regenerate: "npx playwright install or the next Puppeteer run downloads browsers again."
        ),
        Rule(
            id: "uv.cache", title: "uv cache", tier: .safe, platform: .python,
            target: .home([".cache/uv"]),
            regenerate: "uv downloads packages again."
        ),
        Rule(
            id: "poetry.cache", title: "Poetry cache", tier: .safe, platform: .python,
            target: .home(["Library/Caches/pypoetry/cache", "Library/Caches/pypoetry/artifacts"]),
            regenerate: "Poetry downloads packages again."
        ),
        Rule(
            id: "poetry.virtualenvs", title: "Poetry virtualenvs", tier: .review, platform: .python,
            target: .home(["Library/Caches/pypoetry/virtualenvs/*"]),
            regenerate: "poetry install recreates the environment."
        ),
        Rule(
            id: "conda.pkgs", title: "Conda package cache", tier: .review, platform: .python,
            target: .home([
                "miniconda3/pkgs",
                "anaconda3/pkgs",
                "miniforge3/pkgs",
                "opt/miniconda3/pkgs",
                "opt/anaconda3/pkgs",
                ".conda/pkgs",
            ]),
            regenerate: "conda downloads packages again; existing environments keep working."
        ),
        Rule(
            id: "cargo.registry", title: "Cargo registry and git caches", tier: .safe, platform: .rust,
            target: .home([
                ".cargo/registry/cache",
                ".cargo/registry/src",
                ".cargo/registry/index",
                ".cargo/git/checkouts",
                ".cargo/git/db",
            ]),
            regenerate: "cargo downloads crates again on the next build.",
            processGuard: ["cargo"]
        ),
        Rule(
            id: "rustup.downloads", title: "rustup downloads", tier: .safe, platform: .rust,
            target: .home([".rustup/downloads", ".rustup/tmp"]),
            regenerate: "rustup downloads again when it next updates."
        ),
        Rule(
            id: "go.build-cache", title: "Go build cache", tier: .safe, platform: .go,
            target: .home(["Library/Caches/go-build"]),
            regenerate: "go build rebuilds it."
        ),
        Rule(
            id: "go.tooling-caches", title: "Go tooling caches", tier: .safe, platform: .go,
            target: .home(["Library/Caches/gopls", "Library/Caches/golangci-lint"]),
            regenerate: "gopls and golangci-lint rebuild them."
        ),
        Rule(
            id: "go.modules", title: "Go module cache", tier: .review, platform: .go,
            target: .home(["go/pkg/mod"]),
            regenerate: "go mod download fetches modules again."
        ),
        Rule(
            id: "maven.repository", title: "Maven local repository", tier: .review, platform: .jvm,
            target: .home([".m2/repository"]),
            regenerate: "Maven downloads dependencies again; artifacts you mvn install locally are rebuilt by installing them again."
        ),
        Rule(
            id: "jvm.build-tool-caches", title: "sbt, Ivy and Coursier caches", tier: .review, platform: .jvm,
            target: .home([".ivy2/cache", ".sbt/boot", "Library/Caches/Coursier"]),
            regenerate: "sbt downloads dependencies again."
        ),
        Rule(
            id: "kotlin.native", title: "Kotlin/Native toolchains", tier: .review, platform: .jvm,
            target: .home([".konan/*"]),
            regenerate: "Kotlin/Native downloads its toolchain again on the next build."
        ),
        Rule(
            id: "composer.cache", title: "Composer cache", tier: .safe, platform: .php,
            target: .home(["Library/Caches/composer", ".composer/cache", ".cache/composer"]),
            regenerate: "composer install downloads packages again."
        ),
        Rule(
            id: "ruby.caches", title: "Bundler and RubyGems caches", tier: .safe, platform: .ruby,
            target: .home([".bundle/cache", ".gem/specs"]),
            regenerate: "Bundler downloads gems again."
        ),
        Rule(
            id: "nuget.http-cache", title: "NuGet HTTP cache", tier: .safe, platform: .dotnet,
            target: .home([".local/share/NuGet/http-cache", ".local/share/NuGet/v3-cache"]),
            regenerate: "dotnet restore downloads metadata again."
        ),
        Rule(
            id: "nuget.packages", title: "NuGet packages", tier: .review, platform: .dotnet,
            target: .home([".nuget/packages"]),
            regenerate: "dotnet restore downloads packages again."
        ),
        Rule(
            id: "haskell.caches", title: "Haskell package caches", tier: .safe, platform: .otherLanguages,
            target: .home([".cabal/packages", ".stack/pantry", ".ghcup/cache"]),
            regenerate: "cabal and stack download packages again."
        ),
        Rule(
            id: "elixir.hex", title: "Hex package cache", tier: .safe, platform: .otherLanguages,
            target: .home([".hex/packages"]),
            regenerate: "mix deps.get downloads packages again."
        ),
        Rule(
            id: "zig.cache", title: "Zig global cache", tier: .safe, platform: .otherLanguages,
            target: .home([".cache/zig"]),
            regenerate: "zig build rebuilds it."
        ),
        // Precedes VS Code so Code* does not claim the Codex folder.
        Rule(
            id: "codex.caches", title: "Codex caches and logs", tier: .safe, platform: .aiTools,
            target: .home([
                ".codex/log",
                "Library/Application Support/Codex*/Cache",
                "Library/Application Support/Codex*/Code Cache",
                "Library/Application Support/Codex*/GPUCache",
            ]),
            regenerate: "Codex rebuilds its caches and writes new logs.",
            skipsRunningApps: true
        ),
        vscodeFamily(id: "vscode.caches", title: "VS Code caches and logs", folder: "Code*"),
        vscodeFamily(id: "cursor.caches", title: "Cursor caches and logs", folder: "Cursor*"),
        vscodeFamily(id: "windsurf.caches", title: "Windsurf caches and logs", folder: "Windsurf*"),
        vscodeFamily(id: "antigravity.caches", title: "Antigravity caches and logs", folder: "Antigravity*"),
        vscodeFamily(id: "vscodium.caches", title: "VSCodium caches and logs", folder: "VSCodium*"),
        vscodeFamily(id: "kiro.caches", title: "Kiro caches and logs", folder: "Kiro*"),
        Rule(
            id: "jetbrains.caches", title: "JetBrains IDE caches and logs", tier: .safe, platform: .editors,
            target: .home(["Library/Caches/JetBrains/*", "Library/Logs/JetBrains/*"]),
            regenerate: "The IDE rebuilds indexes the next time it opens a project."
        ),
        Rule(
            id: "zed.caches", title: "Zed caches and logs", tier: .safe, platform: .editors,
            target: .home(["Library/Caches/Zed*", "Library/Logs/Zed*"]),
            regenerate: "Zed rebuilds its caches and writes new logs."
        ),
        Rule(
            id: "claude.desktop-caches", title: "Claude desktop caches", tier: .safe, platform: .aiTools,
            target: .home([
                "Library/Application Support/Claude*/Cache",
                "Library/Application Support/Claude*/Code Cache",
                "Library/Application Support/Claude*/GPUCache",
                "Library/Logs/Claude*",
            ]),
            regenerate: "Claude rebuilds its web cache and writes new logs.",
            skipsRunningApps: true
        ),
        Rule(
            id: "claude-code.logs", title: "Claude Code debug logs", tier: .safe, platform: .aiTools,
            target: .home([".claude/debug", "Library/Caches/claude-cli-nodejs"]),
            regenerate: "Claude Code writes new logs as it runs."
        ),
        Rule(
            id: "chatgpt.caches", title: "ChatGPT caches", tier: .safe, platform: .aiTools,
            target: .home(["Library/Caches/com.openai.chat*"]),
            regenerate: "ChatGPT rebuilds its cache on launch.",
            skipsRunningApps: true
        ),
        Rule(
            id: "gemini-cli.temp", title: "Gemini CLI temporary files", tier: .safe, platform: .aiTools,
            target: .home([".gemini/tmp"]),
            regenerate: "Gemini CLI writes new temporary files as it runs."
        ),
        Rule(
            id: "opencode.caches", title: "opencode caches and logs", tier: .safe, platform: .aiTools,
            target: .home([".cache/opencode", ".local/share/opencode/log"]),
            regenerate: "opencode reinstalls its provider packages and writes new logs.",
            processGuard: ["opencode"]
        ),
        Rule(
            id: "ollama.models", title: "Ollama models", tier: .caution, platform: .aiModels,
            target: .home([".ollama/models"]),
            regenerate: "Not regenerable offline: ollama pull downloads the models again.",
            processGuard: ["ollama"]
        ),
        Rule(
            id: "lmstudio.models", title: "LM Studio models", tier: .caution, platform: .aiModels,
            target: .home([".lmstudio/models/*/*", ".cache/lm-studio/models/*/*"]),
            regenerate: "Not regenerable offline: LM Studio downloads the model again.",
            skipsRunningApps: true
        ),
        Rule(
            id: "huggingface.models", title: "Hugging Face models and datasets", tier: .caution, platform: .aiModels,
            target: .home([".cache/huggingface/hub/models--*", ".cache/huggingface/hub/datasets--*"]),
            regenerate: "Not regenerable offline: the next load downloads it again."
        ),
        Rule(
            id: "unity.caches", title: "Unity caches", tier: .safe, platform: .gameEngines,
            target: .home(["Library/Caches/com.unity3d.*", "Library/Unity/cache"]),
            regenerate: "Unity rebuilds its caches and downloads packages again.",
            skipsRunningApps: true
        ),
        Rule(
            id: "godot.caches", title: "Godot caches", tier: .safe, platform: .gameEngines,
            target: .home(["Library/Caches/Godot"]),
            regenerate: "Godot rebuilds its cache.",
            skipsRunningApps: true
        ),
        Rule(
            id: "unreal.ddc", title: "Unreal Engine derived data cache", tier: .review, platform: .gameEngines,
            target: .home(["Library/Application Support/Epic/UnrealEngine/Common/DerivedDataCache"]),
            regenerate: "Unreal rebuilds it, which makes the next editor launch slow."
        ),
        Rule(
            id: "compiler.caches", title: "ccache and sccache", tier: .safe, platform: .devTools,
            target: .home(["Library/Caches/ccache", "Library/Caches/Mozilla.sccache"]),
            regenerate: "The next build fills the cache again."
        ),
        Rule(
            id: "devops.caches", title: "Terraform, pre-commit and Firebase caches", tier: .safe, platform: .devTools,
            target: .home([".terraform.d/plugin-cache", ".cache/pre-commit", ".cache/firebase/emulators"]),
            regenerate: "Each tool downloads what it needs again."
        ),
        Rule(
            id: "minikube.cache", title: "minikube cache", tier: .safe, platform: .devTools,
            target: .home([".minikube/cache"]),
            regenerate: "minikube downloads images again."
        ),
        Rule(
            id: "vagrant.boxes", title: "Vagrant boxes", tier: .caution, platform: .devTools,
            target: .home([".vagrant.d/boxes/*"]),
            regenerate: "Not regenerable offline: vagrant box add downloads the box again."
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
            excluding: ["Library/Logs/DevDuster"],
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
            id: "pub.cache", title: "Dart pub cache", tier: .review, platform: .flutter,
            target: .home([".pub-cache/hosted", ".pub-cache/git", ".pub-cache/_temp"]),
            regenerate: "flutter pub get downloads packages again; globally activated tools are kept."
        ),
        Rule(
            id: "docker.prune", title: "Docker unused data (estimate)", tier: .review, platform: .devTools,
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
            id: "project.flutter-build", title: "Flutter build output", tier: .review, platform: .flutter,
            target: .project(directory: "build", markers: ["pubspec.yaml"]),
            regenerate: "flutter build recreates it."
        ),
        Rule(
            id: "project.dart-tool", title: "Dart tool folders", tier: .review, platform: .flutter,
            target: .project(directory: ".dart_tool", markers: ["pubspec.yaml"]),
            regenerate: "flutter pub get recreates it."
        ),
        Rule(
            id: "project.gradle-build", title: "Gradle build output", tier: .review, platform: .android,
            target: .project(directory: "build", markers: gradleMarkers),
            regenerate: "The next Gradle build recreates it."
        ),
        Rule(
            id: "project.gradle", title: "Gradle project caches", tier: .review, platform: .android,
            target: .project(directory: ".gradle", markers: gradleMarkers),
            regenerate: "The next Gradle build recreates it."
        ),
        Rule(
            id: "project.pods", title: "CocoaPods Pods", tier: .review, platform: .apple,
            target: .project(directory: "Pods", markers: ["Podfile"]),
            regenerate: "pod install recreates it."
        ),
        Rule(
            id: "project.ios-symlinks", title: "Flutter iOS plugin links", tier: .review, platform: .flutter,
            target: .project(directory: ".symlinks", markers: ["Podfile"]),
            regenerate: "flutter pub get recreates it."
        ),
        Rule(
            id: "project.node-modules", title: "node_modules", tier: .review, platform: .javascript,
            target: .project(directory: "node_modules", markers: packageMarkers),
            regenerate: "npm, yarn or pnpm install recreates it."
        ),
        Rule(
            id: "project.cargo-target", title: "Cargo target", tier: .review, platform: .rust,
            target: .project(directory: "target", markers: ["Cargo.toml"]),
            regenerate: "cargo build recreates it."
        ),
        Rule(
            id: "project.next", title: "Next.js build output", tier: .review, platform: .javascript,
            target: .project(directory: ".next", markers: ["next.config.js", "next.config.mjs", "next.config.ts"]),
            regenerate: "next build recreates it."
        ),
        Rule(
            id: "project.nuxt", title: "Nuxt build output", tier: .review, platform: .javascript,
            target: .project(directory: ".nuxt", markers: ["nuxt.config.ts", "nuxt.config.js"]),
            regenerate: "nuxt build recreates it."
        ),
        Rule(
            id: "project.turbo", title: "Turborepo cache", tier: .review, platform: .javascript,
            target: .project(directory: ".turbo", markers: ["turbo.json"]),
            regenerate: "The next turbo run recreates it."
        ),
        Rule(
            id: "project.parcel", title: "Parcel cache", tier: .review, platform: .javascript,
            target: .project(directory: ".parcel-cache", markers: packageMarkers),
            regenerate: "The next Parcel build recreates it."
        ),
        Rule(
            id: "project.svelte-kit", title: "SvelteKit output", tier: .review, platform: .javascript,
            target: .project(directory: ".svelte-kit", markers: ["svelte.config.js", "svelte.config.ts"]),
            regenerate: "vite build recreates it."
        ),
        Rule(
            id: "project.angular", title: "Angular cache", tier: .review, platform: .javascript,
            target: .project(directory: ".angular", markers: ["angular.json"]),
            regenerate: "ng build recreates it."
        ),
        Rule(
            id: "project.expo", title: "Expo project cache", tier: .review, platform: .javascript,
            target: .project(directory: ".expo", markers: packageMarkers),
            regenerate: "expo start recreates it."
        ),
        Rule(
            id: "project.venv", title: "Python virtual environments", tier: .review, platform: .python,
            target: .project(directory: ".venv", markers: ["pyproject.toml", "requirements.txt", "setup.py", "Pipfile", "uv.lock", "poetry.lock"]),
            regenerate: "uv sync or pip install -r requirements.txt recreates it."
        ),
        Rule(
            id: "project.tox", title: "tox environments", tier: .review, platform: .python,
            target: .project(directory: ".tox", markers: ["tox.ini"]),
            regenerate: "tox recreates them."
        ),
        Rule(
            id: "project.pytest-cache", title: "pytest cache", tier: .review, platform: .python,
            target: .project(directory: ".pytest_cache", markers: pythonToolMarkers),
            regenerate: "pytest recreates it."
        ),
        Rule(
            id: "project.mypy-cache", title: "mypy cache", tier: .review, platform: .python,
            target: .project(directory: ".mypy_cache", markers: pythonToolMarkers),
            regenerate: "mypy recreates it."
        ),
        Rule(
            id: "project.ruff-cache", title: "Ruff cache", tier: .review, platform: .python,
            target: .project(directory: ".ruff_cache", markers: pythonToolMarkers),
            regenerate: "ruff recreates it."
        ),
        Rule(
            id: "project.maven-target", title: "Maven target", tier: .review, platform: .jvm,
            target: .project(directory: "target", markers: ["pom.xml"]),
            regenerate: "mvn package recreates it."
        ),
        Rule(
            id: "project.cxx", title: "Android native build output", tier: .review, platform: .android,
            target: .project(directory: ".cxx", markers: gradleMarkers),
            regenerate: "The next Gradle build recreates it."
        ),
        Rule(
            id: "project.swiftpm-build", title: "Swift package build output", tier: .review, platform: .apple,
            target: .project(directory: ".build", markers: ["Package.swift"]),
            regenerate: "swift build recreates it."
        ),
        Rule(
            id: "project.composer-vendor", title: "Composer vendor", tier: .review, platform: .php,
            target: .project(directory: "vendor", markers: ["composer.json"]),
            regenerate: "composer install recreates it."
        ),
        Rule(
            id: "project.stack-work", title: "Stack build output", tier: .review, platform: .otherLanguages,
            target: .project(directory: ".stack-work", markers: ["stack.yaml"]),
            regenerate: "stack build recreates it."
        ),
        Rule(
            id: "project.mix-build", title: "Mix build output", tier: .review, platform: .otherLanguages,
            target: .project(directory: "_build", markers: ["mix.exs"]),
            regenerate: "mix compile recreates it."
        ),
        Rule(
            id: "project.zig-cache", title: "Zig build cache", tier: .review, platform: .otherLanguages,
            target: .project(directory: ".zig-cache", markers: ["build.zig"]),
            regenerate: "zig build recreates it."
        ),
        Rule(
            id: "project.terraform", title: "Terraform providers", tier: .review, platform: .devTools,
            target: .project(directory: ".terraform", markers: [".terraform.lock.hcl"]),
            regenerate: "terraform init recreates it."
        ),
        Rule(
            id: "project.python-venv", title: "Python virtual environments", tier: .review, platform: .python,
            target: .project(directory: "venv", markers: pythonToolMarkers, proof: "pyvenv.cfg"),
            regenerate: "python -m venv venv and pip install -r requirements.txt recreate it."
        ),
        Rule(
            id: "project.kotlin", title: "Kotlin compiler data", tier: .review, platform: .jvm,
            target: .project(directory: ".kotlin", markers: gradleMarkers + ["settings.gradle", "settings.gradle.kts"]),
            regenerate: "The next Gradle build recreates it."
        ),
        Rule(
            id: "project.dotnet-obj", title: ".NET intermediate output", tier: .review, platform: .dotnet,
            target: .project(directory: "obj", markers: dotnetMarkers, proof: "project.assets.json"),
            regenerate: "dotnet build recreates it."
        ),
        Rule(
            id: "project.dotnet-bin", title: ".NET build output", tier: .review, platform: .dotnet,
            target: .project(directory: "bin", markers: dotnetMarkers, proof: "Debug"),
            regenerate: "dotnet build recreates it."
        ),
        Rule(
            id: "project.dotnet-bin-release", title: ".NET build output", tier: .review, platform: .dotnet,
            target: .project(directory: "bin", markers: dotnetMarkers, proof: "Release"),
            regenerate: "dotnet build -c Release recreates it."
        ),
        Rule(
            id: "project.cmake-build", title: "CMake build folders", tier: .review, platform: .otherLanguages,
            target: .project(directory: "build", markers: ["CMakeLists.txt"], proof: "CMakeCache.txt"),
            regenerate: "cmake and the next build recreate it."
        ),
        Rule(
            id: "project.clion-debug", title: "CLion CMake builds", tier: .review, platform: .otherLanguages,
            target: .project(directory: "cmake-build-debug", markers: ["CMakeLists.txt"], proof: "CMakeCache.txt"),
            regenerate: "CLion recreates it on the next build."
        ),
        Rule(
            id: "project.clion-release", title: "CLion CMake builds", tier: .review, platform: .otherLanguages,
            target: .project(directory: "cmake-build-release", markers: ["CMakeLists.txt"], proof: "CMakeCache.txt"),
            regenerate: "CLion recreates it on the next build."
        ),
        Rule(
            id: "project.cabal-dist", title: "Cabal build output", tier: .review, platform: .otherLanguages,
            target: .project(directory: "dist-newstyle", markers: ["cabal.project", "*.cabal"]),
            regenerate: "cabal build recreates it."
        ),
        Rule(
            id: "project.mix-deps", title: "Mix dependencies", tier: .review, platform: .otherLanguages,
            target: .project(directory: "deps", markers: ["mix.exs"]),
            regenerate: "mix deps.get recreates it."
        ),
        Rule(
            id: "project.zig-cache-legacy", title: "Zig build cache", tier: .review, platform: .otherLanguages,
            target: .project(directory: "zig-cache", markers: ["build.zig"]),
            regenerate: "zig build recreates it."
        ),
        Rule(
            id: "project.zig-out", title: "Zig build output", tier: .review, platform: .otherLanguages,
            target: .project(directory: "zig-out", markers: ["build.zig"]),
            regenerate: "zig build recreates it."
        ),
        Rule(
            id: "project.unity-library", title: "Unity Library folders", tier: .review, platform: .gameEngines,
            target: .project(directory: "Library", markers: [unityMarker]),
            regenerate: "Unity reimports assets the next time the project opens."
        ),
        Rule(
            id: "project.unity-temp", title: "Unity temp folders", tier: .review, platform: .gameEngines,
            target: .project(directory: "Temp", markers: [unityMarker]),
            regenerate: "Unity recreates it while the project is open."
        ),
        Rule(
            id: "project.unity-obj", title: "Unity script build output", tier: .review, platform: .gameEngines,
            target: .project(directory: "obj", markers: [unityMarker]),
            regenerate: "Unity and the IDE recreate it on the next script build."
        ),
        Rule(
            id: "project.unreal-intermediate", title: "Unreal intermediate files", tier: .review, platform: .gameEngines,
            target: .project(directory: "Intermediate", markers: unrealMarkers),
            regenerate: "Unreal recreates it on the next build."
        ),
        Rule(
            id: "project.unreal-ddc", title: "Unreal project derived data", tier: .review, platform: .gameEngines,
            target: .project(directory: "DerivedDataCache", markers: unrealMarkers),
            regenerate: "Unreal rebuilds it as the editor loads assets."
        ),
    ]

    private static let gradleDaemon = "GradleDaemon"
    private static let gradleMarkers = ["build.gradle", "build.gradle.kts"]
    private static let packageMarkers = ["package.json"]
    private static let dotnetMarkers = ["*.csproj", "*.fsproj", "*.vbproj"]
    private static let unityMarker = "ProjectSettings/ProjectVersion.txt"
    private static let unrealMarkers = ["*.uproject", "*.uplugin"]
    private static let pythonToolMarkers = ["pyproject.toml", "setup.cfg", "setup.py", "pytest.ini", "tox.ini", "requirements.txt"]
    private static let vscodeFolders = ["Cache", "Code Cache", "GPUCache", "CachedData", "CachedExtensionVSIXs", "CachedProfilesData", "logs", "Crashpad/completed"]

    private static func vscodeFamily(id: String, title: String, folder glob: String) -> Rule {
        Rule(
            id: id, title: title, tier: .safe, platform: .editors,
            target: .home(vscodeFolders.map { "Library/Application Support/\(glob)/\($0)" }),
            regenerate: "The editor rebuilds its caches and writes new logs.",
            skipsRunningApps: true
        )
    }
}
