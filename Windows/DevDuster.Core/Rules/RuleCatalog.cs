namespace DevDuster.Core.Rules;

public sealed class RuleCatalog
{
    // A Gradle daemon is a plain java process on Windows, so any java run keeps its caches.
    private static readonly string[] Java = ["java"];
    private static readonly string[] GradleMarkers = ["build.gradle", "build.gradle.kts"];
    private static readonly string[] PackageMarkers = ["package.json"];
    private static readonly string[] DotNetMarkers = ["*.csproj", "*.fsproj", "*.vbproj"];
    private static readonly string[] UnrealMarkers = ["*.uproject", "*.uplugin"];
    private static readonly string[] UnityMarkers = ["ProjectSettings/ProjectVersion.txt"];
    private static readonly string[] PythonMarkers = ["pyproject.toml", "setup.cfg", "setup.py", "pytest.ini", "tox.ini", "requirements.txt"];
    private static readonly string[] ElectronFolders = ["Cache", "Code Cache", "GPUCache", "DawnCache"];
    private static readonly string[] EditorFolders = [.. ElectronFolders, "CachedData", "CachedExtensionVSIXs", "CachedProfilesData", "logs"];

    public static readonly Rule UserSelected = new(
        "user.selected", "Selected by you", Tier.Review, RulePlatform.Windows, new UserSelectedTarget(),
        "Chosen by you; not regenerated.");

    public static readonly Rule Leftover = new(
        "uninstall.leftover", "Leftover folder", Tier.Caution, RulePlatform.Windows, new LeftoverTarget(),
        "Reinstalling the program creates a fresh one; its old settings are gone.");

    public RuleCatalog(UserFolders? folders = null)
    {
        Folders = folders ?? UserFolders.Current();
        Rules = BuiltIn;
    }

    public UserFolders Folders { get; }
    public IReadOnlyList<Rule> Rules { get; }

    private static readonly Rule[] BuiltIn =
    [
        // Order is precedence: earlier rules claim paths first, so specific rules precede the broad globs.
        Folder("android.sdk-cache", "Android SDK Manager cache", Tier.Safe, RulePlatform.Android, "The SDK Manager downloads its package lists again.", "~/.android/cache"),
        FolderSet("gradle.daemon", "Gradle daemon logs", Tier.Safe, RulePlatform.Android, "Gradle recreates them when a daemon starts.", ["~/.gradle/daemon/*"], guard: Java),
        FolderSet("gradle.build-cache", "Gradle build cache", Tier.Safe, RulePlatform.Android, "Gradle refills it on the next build.", ["~/.gradle/caches/build-cache-*"], guard: Java),
        Folder("npm.cache", "npm cache", Tier.Safe, RulePlatform.JavaScript, "npm install downloads packages again.", "%LOCAL%/npm-cache/_cacache", "%LOCAL%/npm-cache/_npx", "%LOCAL%/npm-cache/_logs", "%ROAMING%/npm-cache/_cacache", "%ROAMING%/npm-cache/_npx"),
        Folder("yarn.cache", "Yarn cache", Tier.Safe, RulePlatform.JavaScript, "yarn install downloads packages again.", "%LOCAL%/Yarn/Cache", "%LOCAL%/Yarn/Berry/cache"),
        Folder("pnpm.store", "pnpm store", Tier.Safe, RulePlatform.JavaScript, "pnpm install downloads packages again; existing node_modules keep working.", "%LOCAL%/pnpm/store", "%LOCAL%/pnpm-cache"),
        Folder("bun.cache", "Bun cache", Tier.Safe, RulePlatform.JavaScript, "bun install downloads packages again.", "~/.bun/install/cache"),
        Folder("deno.cache", "Deno cache", Tier.Safe, RulePlatform.JavaScript, "Deno downloads modules again on the next run.", "%LOCAL%/deno"),
        Folder("node.tooling-caches", "Node tooling caches", Tier.Safe, RulePlatform.JavaScript, "Each tool downloads what it needs again.", "%LOCAL%/node-gyp/Cache", "%LOCAL%/Microsoft/TypeScript", "%LOCAL%/electron/Cache", "%LOCAL%/electron-builder/Cache", "%LOCAL%/Cypress/Cache"),
        Folder("browsers.testing", "Playwright and Puppeteer browsers", Tier.Review, RulePlatform.JavaScript, "npx playwright install or the next Puppeteer run downloads browsers again.", "%LOCAL%/ms-playwright/*", "~/.cache/puppeteer/*"),
        Folder("pip.cache", "pip cache", Tier.Safe, RulePlatform.Python, "pip downloads wheels again when needed.", "%LOCAL%/pip/Cache"),
        Folder("uv.cache", "uv cache", Tier.Safe, RulePlatform.Python, "uv downloads packages again.", "%LOCAL%/uv/cache"),
        Folder("poetry.cache", "Poetry cache", Tier.Safe, RulePlatform.Python, "Poetry downloads packages again.", "%LOCAL%/pypoetry/Cache/cache", "%LOCAL%/pypoetry/Cache/artifacts"),
        Folder("poetry.virtualenvs", "Poetry virtualenvs", Tier.Review, RulePlatform.Python, "poetry install recreates the environment.", "%LOCAL%/pypoetry/Cache/virtualenvs/*"),
        Folder("conda.pkgs", "Conda package cache", Tier.Review, RulePlatform.Python, "conda downloads packages again; existing environments keep working.", "~/miniconda3/pkgs", "~/anaconda3/pkgs", "~/miniforge3/pkgs", "~/.conda/pkgs", "%LOCAL%/miniconda3/pkgs", "%LOCAL%/miniforge3/pkgs"),
        FolderSet("cargo.registry", "Cargo registry and git caches", Tier.Safe, RulePlatform.Rust, "cargo downloads crates again on the next build.", ["~/.cargo/registry/cache", "~/.cargo/registry/src", "~/.cargo/registry/index", "~/.cargo/git/checkouts", "~/.cargo/git/db"], guard: ["cargo"]),
        Folder("rustup.downloads", "rustup downloads", Tier.Safe, RulePlatform.Rust, "rustup downloads again when it next updates.", "~/.rustup/downloads", "~/.rustup/tmp"),
        Folder("go.build-cache", "Go build cache", Tier.Safe, RulePlatform.Go, "go build rebuilds it.", "%LOCAL%/go-build"),
        Folder("go.tooling-caches", "Go tooling caches", Tier.Safe, RulePlatform.Go, "gopls and golangci-lint rebuild them.", "%LOCAL%/gopls", "%LOCAL%/golangci-lint"),
        Folder("go.modules", "Go module cache", Tier.Review, RulePlatform.Go, "go mod download fetches modules again.", "~/go/pkg/mod"),
        FolderSet("maven.repository", "Maven local repository", Tier.Review, RulePlatform.Jvm, "Maven downloads dependencies again; artifacts you mvn install locally must be installed again.", ["~/.m2/repository"], guard: Java),
        FolderSet("jvm.build-tool-caches", "sbt, Ivy and Coursier caches", Tier.Review, RulePlatform.Jvm, "sbt downloads dependencies again.", ["~/.ivy2/cache", "~/.sbt/boot", "%LOCAL%/Coursier/cache"], guard: Java),
        FolderSet("kotlin.native", "Kotlin/Native toolchains", Tier.Review, RulePlatform.Jvm, "Kotlin/Native downloads its toolchain again on the next build.", ["~/.konan/*"], guard: Java),
        Folder("composer.cache", "Composer cache", Tier.Safe, RulePlatform.Php, "composer install downloads packages again.", "%LOCAL%/Composer/cache", "%LOCAL%/Composer/files", "%LOCAL%/Composer/repo", "%LOCAL%/Composer/vcs"),
        Folder("ruby.caches", "Bundler and RubyGems caches", Tier.Safe, RulePlatform.Ruby, "Bundler downloads gems again.", "~/.bundle/cache", "~/.gem/specs"),
        Folder("nuget.http-cache", "NuGet HTTP cache", Tier.Safe, RulePlatform.DotNet, "dotnet restore downloads metadata again.", "%LOCAL%/NuGet/v3-cache", "%LOCAL%/NuGet/plugins-cache"),
        Folder("nuget.packages", "NuGet packages", Tier.Review, RulePlatform.DotNet, "dotnet restore downloads packages again.", "~/.nuget/packages"),
        Folder("haskell.caches", "Haskell package caches", Tier.Safe, RulePlatform.OtherLanguages, "cabal and stack download packages again.", "%ROAMING%/cabal/packages", "%LOCAL%/cabal/packages", "%ROAMING%/stack/pantry"),
        Folder("elixir.hex", "Hex package cache", Tier.Safe, RulePlatform.OtherLanguages, "mix deps.get downloads packages again.", "~/.hex/packages"),
        Folder("zig.cache", "Zig global cache", Tier.Safe, RulePlatform.OtherLanguages, "zig build rebuilds it.", "%LOCAL%/zig"),
        Folder("vcpkg.archives", "vcpkg binary cache", Tier.Review, RulePlatform.OtherLanguages, "vcpkg builds the packages again.", "%LOCAL%/vcpkg/archives", "%LOCAL%/vcpkg/downloads"),
        // Precedes VS Code so Code* does not claim the Codex folder.
        Electron("codex.caches", "Codex caches", RulePlatform.AiTools, "Codex*", ElectronFolders, "~/.codex/log"),
        Electron("vscode.caches", "VS Code caches and logs", RulePlatform.Editors, "Code*", EditorFolders),
        Electron("cursor.caches", "Cursor caches and logs", RulePlatform.Editors, "Cursor*", EditorFolders),
        Electron("windsurf.caches", "Windsurf caches and logs", RulePlatform.Editors, "Windsurf*", EditorFolders),
        Electron("antigravity.caches", "Antigravity caches and logs", RulePlatform.Editors, "Antigravity*", EditorFolders),
        Electron("vscodium.caches", "VSCodium caches and logs", RulePlatform.Editors, "VSCodium*", EditorFolders),
        Electron("kiro.caches", "Kiro caches and logs", RulePlatform.Editors, "Kiro*", EditorFolders),
        FolderSet("jetbrains.caches", "JetBrains IDE caches and logs", Tier.Safe, RulePlatform.Editors, "The IDE rebuilds indexes the next time it opens a project.", ["%LOCAL%/JetBrains/*/caches", "%LOCAL%/JetBrains/*/index", "%LOCAL%/JetBrains/*/log", "%LOCAL%/JetBrains/*/tmp"], guard: ["idea64", "pycharm64", "webstorm64", "phpstorm64", "rider64", "clion64", "goland64", "rubymine64", "datagrip64", "rustrover64"]),
        FolderSet("visual-studio.component-cache", "Visual Studio component cache", Tier.Safe, RulePlatform.Editors, "Visual Studio rebuilds it on the next start.", ["%LOCAL%/Microsoft/VisualStudio/*/ComponentModelCache"], guard: ["devenv"]),
        FolderSet("visual-studio.web-cache", "Visual Studio web cache", Tier.Safe, RulePlatform.Editors, "Visual Studio downloads it again.", ["%LOCAL%/Microsoft/WebsiteCache"], guard: ["devenv"]),
        FolderSet("zed.logs", "Zed logs", Tier.Safe, RulePlatform.Editors, "Zed writes new logs.", ["%LOCAL%/Zed/logs"], guard: ["zed"]),
        Electron("claude.desktop-caches", "Claude desktop caches", RulePlatform.AiTools, "Claude*", [.. ElectronFolders, "logs"]),
        FolderSet("claude-code.logs", "Claude Code debug logs", Tier.Safe, RulePlatform.AiTools, "Claude Code writes new logs as it runs.", ["~/.claude/debug"], guard: ["claude"]),
        Folder("gemini-cli.temp", "Gemini CLI temporary files", Tier.Safe, RulePlatform.AiTools, "Gemini CLI writes new temporary files as it runs.", "~/.gemini/tmp"),
        FolderSet("opencode.caches", "opencode caches and logs", Tier.Safe, RulePlatform.AiTools, "opencode reinstalls its provider packages and writes new logs.", ["~/.cache/opencode", "~/.local/share/opencode/log"], guard: ["opencode"]),
        FolderSet("ollama.models", "Ollama models", Tier.Caution, RulePlatform.AiModels, "Not regenerable offline: ollama pull downloads the models again.", ["~/.ollama/models"], guard: ["ollama", "ollama app"]),
        FolderSet("lmstudio.models", "LM Studio models", Tier.Caution, RulePlatform.AiModels, "Not regenerable offline: LM Studio downloads the model again.", ["~/.lmstudio/models/*/*", "~/.cache/lm-studio/models/*/*"], guard: ["LM Studio"]),
        Folder("huggingface.models", "Hugging Face models and datasets", Tier.Caution, RulePlatform.AiModels, "Not regenerable offline: the next load downloads it again.", "~/.cache/huggingface/hub/models--*", "~/.cache/huggingface/hub/datasets--*"),
        FolderSet("unity.caches", "Unity caches", Tier.Safe, RulePlatform.GameEngines, "Unity rebuilds its caches and downloads packages again.", ["%LOCAL%/Unity/cache", "%LOCAL%/Unity/Caches"], guard: ["Unity", "Unity Hub"]),
        Folder("godot.caches", "Godot caches", Tier.Safe, RulePlatform.GameEngines, "Godot rebuilds its cache.", "%LOCAL%/Godot/cache"),
        FolderSet("unreal.ddc", "Unreal Engine derived data cache", Tier.Review, RulePlatform.GameEngines, "Unreal rebuilds it, which makes the next editor launch slow.", ["%LOCAL%/UnrealEngine/Common/DerivedDataCache"], guard: ["UnrealEditor"]),
        Folder("compiler.caches", "ccache and sccache", Tier.Safe, RulePlatform.DevTools, "The next build fills the cache again.", "%LOCAL%/ccache", "%LOCAL%/Mozilla/sccache"),
        Folder("devops.caches", "Terraform, pre-commit and Firebase caches", Tier.Safe, RulePlatform.DevTools, "Each tool downloads what it needs again.", "%ROAMING%/terraform.d/plugin-cache", "~/.cache/pre-commit", "~/.cache/firebase/emulators"),
        Folder("minikube.cache", "minikube cache", Tier.Safe, RulePlatform.DevTools, "minikube downloads images again.", "~/.minikube/cache"),
        Folder("scoop.cache", "Scoop downloads", Tier.Safe, RulePlatform.DevTools, "Scoop downloads installers again.", "~/scoop/cache"),
        Folder("vagrant.boxes", "Vagrant boxes", Tier.Caution, RulePlatform.DevTools, "Not regenerable offline: vagrant box add downloads the box again.", "~/.vagrant.d/boxes/*"),
        Electron("electron.caches", "Electron app caches", RulePlatform.Windows, "*", ElectronFolders),
        FolderSet("android-studio.old", "Old Android Studio caches", Tier.Review, RulePlatform.Android, "Only versions older than the newest install; they are never read again.", ["%LOCAL%/Google/AndroidStudio*"], guard: ["studio64"], pick: RulePick.AllButNewestVersion),
        Folder("windows.crash-dumps", "Crash dumps", Tier.Safe, RulePlatform.Windows, "Windows writes a new dump when an app crashes.", "%LOCAL%/CrashDumps/*"),
        Folder("windows.error-reports", "Windows error reports", Tier.Safe, RulePlatform.Windows, "Windows writes new reports when apps fail.", "%LOCAL%/Microsoft/Windows/WER/ReportArchive/*", "%LOCAL%/Microsoft/Windows/WER/ReportQueue/*"),
        Folder("windows.shader-cache", "Shader caches", Tier.Safe, RulePlatform.Windows, "Games and apps compile shaders again.", "%LOCAL%/D3DSCache/*", "%LOCAL%/NVIDIA/DXCache/*", "%LOCAL%/NVIDIA/GLCache/*", "%LOCAL%/AMD/DxCache/*"),
        FolderSet("windows.temp", "Temporary files", Tier.Safe, RulePlatform.Windows, "Apps write new temporary files as they run; only files untouched for 7 days.", ["%TEMP%/*"], minAgeDays: 7),
        FolderSet("gradle.caches", "Old Gradle caches", Tier.Review, RulePlatform.Android, "Only versions older than the newest; Gradle downloads again if an old one is used.", ["~/.gradle/caches/?.*", "~/.gradle/caches/??.*"], guard: Java, pick: RulePick.AllButNewestVersion),
        FolderSet("gradle.wrapper", "Old Gradle wrapper distributions", Tier.Review, RulePlatform.Android, "The wrapper downloads a version again when a project asks for it.", ["~/.gradle/wrapper/dists/*"], guard: Java, pick: RulePick.AllButNewestVersion),
        FolderSet("pub.cache", "Dart pub cache", Tier.Review, RulePlatform.Flutter, "flutter pub get downloads packages again; globally activated tools are kept.", ["%LOCAL%/Pub/Cache/hosted", "%LOCAL%/Pub/Cache/git", "%LOCAL%/Pub/Cache/_temp"], guard: ["dart", "dartvm"]),
        new("docker.prune", "Docker unused data (estimate)", Tier.Review, RulePlatform.DevTools, new DockerPruneTarget(), "Runs docker system prune -f: stopped containers, unused networks, dangling images and build cache."),
        FolderSet("android.avds", "Android emulators (AVDs)", Tier.Caution, RulePlatform.Android, "Recreate in Device Manager; the emulator's data is lost.", ["~/.android/avd/*.avd"], guard: ["emulator", "qemu-system-x86_64", "qemu-system-aarch64"]),
        FolderSet("android.system-images", "Unused Android system images", Tier.Caution, RulePlatform.Android, "Images no AVD uses; the SDK Manager downloads them again.", ["%LOCAL%/Android/Sdk/system-images/*/*/*"], pick: RulePick.UnreferencedByAvds),
        FolderSet("android.ndk", "Old Android NDKs", Tier.Caution, RulePlatform.Android, "Only versions older than the newest; the SDK Manager downloads them again.", ["%LOCAL%/Android/Sdk/ndk/*"], pick: RulePick.AllButNewestVersion),
        FolderSet("android.build-tools", "Old Android build tools", Tier.Caution, RulePlatform.Android, "Only versions older than the newest; Gradle downloads one again if a project pins it.", ["%LOCAL%/Android/Sdk/build-tools/*"], pick: RulePick.AllButNewestVersion),
        FolderSet("android.platforms", "Old Android SDK platforms", Tier.Caution, RulePlatform.Android, "Only versions older than the newest; Gradle downloads one again if a project compiles against it.", ["%LOCAL%/Android/Sdk/platforms/*"], pick: RulePick.AllButNewestVersion),
        Folder("ios.backups", "iPhone and iPad backups", Tier.Caution, RulePlatform.Windows, "Not regenerable: back up the device again first.", "%ROAMING%/Apple Computer/MobileSync/Backup/*", "~/Apple/MobileSync/Backup/*"),
        Project("flutter-build", "Flutter build output", RulePlatform.Flutter, "build", ["pubspec.yaml"], "flutter build recreates it."),
        Project("dart-tool", "Dart tool folders", RulePlatform.Flutter, ".dart_tool", ["pubspec.yaml"], "flutter pub get recreates it."),
        Project("gradle-build", "Gradle build output", RulePlatform.Android, "build", GradleMarkers, "The next Gradle build recreates it."),
        Project("gradle", "Gradle project caches", RulePlatform.Android, ".gradle", GradleMarkers, "The next Gradle build recreates it."),
        Project("cxx", "Android native build output", RulePlatform.Android, ".cxx", GradleMarkers, "The next Gradle build recreates it."),
        Project("node-modules", "node_modules", RulePlatform.JavaScript, "node_modules", PackageMarkers, "npm, yarn or pnpm install recreates it."),
        Project("next", "Next.js build output", RulePlatform.JavaScript, ".next", ["next.config.js", "next.config.mjs", "next.config.ts"], "next build recreates it."),
        Project("nuxt", "Nuxt build output", RulePlatform.JavaScript, ".nuxt", ["nuxt.config.ts", "nuxt.config.js"], "nuxt build recreates it."),
        Project("turbo", "Turborepo cache", RulePlatform.JavaScript, ".turbo", ["turbo.json"], "The next turbo run recreates it."),
        Project("parcel", "Parcel cache", RulePlatform.JavaScript, ".parcel-cache", PackageMarkers, "The next Parcel build recreates it."),
        Project("svelte-kit", "SvelteKit output", RulePlatform.JavaScript, ".svelte-kit", ["svelte.config.js", "svelte.config.ts"], "vite build recreates it."),
        Project("angular", "Angular cache", RulePlatform.JavaScript, ".angular", ["angular.json"], "ng build recreates it."),
        Project("expo", "Expo project cache", RulePlatform.JavaScript, ".expo", PackageMarkers, "expo start recreates it."),
        Project("venv", "Python virtual environments", RulePlatform.Python, ".venv", ["pyproject.toml", "requirements.txt", "setup.py", "Pipfile", "uv.lock", "poetry.lock"], "uv sync or pip install -r requirements.txt recreates it."),
        Project("python-venv", "Python virtual environments", RulePlatform.Python, "venv", PythonMarkers, "python -m venv venv and pip install -r requirements.txt recreate it.", "pyvenv.cfg"),
        Project("tox", "tox environments", RulePlatform.Python, ".tox", ["tox.ini"], "tox recreates them."),
        Project("pytest-cache", "pytest cache", RulePlatform.Python, ".pytest_cache", PythonMarkers, "pytest recreates it."),
        Project("mypy-cache", "mypy cache", RulePlatform.Python, ".mypy_cache", PythonMarkers, "mypy recreates it."),
        Project("ruff-cache", "Ruff cache", RulePlatform.Python, ".ruff_cache", PythonMarkers, "ruff recreates it."),
        Project("cargo-target", "Cargo target", RulePlatform.Rust, "target", ["Cargo.toml"], "cargo build recreates it."),
        Project("maven-target", "Maven target", RulePlatform.Jvm, "target", ["pom.xml"], "mvn package recreates it."),
        Project("kotlin", "Kotlin compiler data", RulePlatform.Jvm, ".kotlin", [.. GradleMarkers, "settings.gradle", "settings.gradle.kts"], "The next Gradle build recreates it."),
        Project("composer-vendor", "Composer vendor", RulePlatform.Php, "vendor", ["composer.json"], "composer install recreates it."),
        Project("dotnet-obj", ".NET intermediate output", RulePlatform.DotNet, "obj", DotNetMarkers, "dotnet build recreates it.", "project.assets.json"),
        Project("dotnet-bin", ".NET build output", RulePlatform.DotNet, "bin", DotNetMarkers, "dotnet build recreates it.", "Debug"),
        Project("dotnet-bin-release", ".NET build output", RulePlatform.DotNet, "bin", DotNetMarkers, "dotnet build -c Release recreates it.", "Release"),
        Project("cmake-build", "CMake build folders", RulePlatform.OtherLanguages, "build", ["CMakeLists.txt"], "cmake and the next build recreate it.", "CMakeCache.txt"),
        Project("clion-debug", "CLion CMake builds", RulePlatform.OtherLanguages, "cmake-build-debug", ["CMakeLists.txt"], "CLion recreates it on the next build.", "CMakeCache.txt"),
        Project("clion-release", "CLion CMake builds", RulePlatform.OtherLanguages, "cmake-build-release", ["CMakeLists.txt"], "CLion recreates it on the next build.", "CMakeCache.txt"),
        Project("stack-work", "Stack build output", RulePlatform.OtherLanguages, ".stack-work", ["stack.yaml"], "stack build recreates it."),
        Project("cabal-dist", "Cabal build output", RulePlatform.OtherLanguages, "dist-newstyle", ["cabal.project", "*.cabal"], "cabal build recreates it."),
        Project("mix-build", "Mix build output", RulePlatform.OtherLanguages, "_build", ["mix.exs"], "mix compile recreates it."),
        Project("mix-deps", "Mix dependencies", RulePlatform.OtherLanguages, "deps", ["mix.exs"], "mix deps.get recreates it."),
        Project("zig-cache", "Zig build cache", RulePlatform.OtherLanguages, ".zig-cache", ["build.zig"], "zig build recreates it."),
        Project("zig-cache-legacy", "Zig build cache", RulePlatform.OtherLanguages, "zig-cache", ["build.zig"], "zig build recreates it."),
        Project("zig-out", "Zig build output", RulePlatform.OtherLanguages, "zig-out", ["build.zig"], "zig build recreates it."),
        Project("unity-library", "Unity Library folders", RulePlatform.GameEngines, "Library", UnityMarkers, "Unity reimports assets the next time the project opens."),
        Project("unity-temp", "Unity temp folders", RulePlatform.GameEngines, "Temp", UnityMarkers, "Unity recreates it while the project is open."),
        Project("unity-obj", "Unity script build output", RulePlatform.GameEngines, "obj", UnityMarkers, "Unity and the IDE recreate it on the next script build."),
        Project("unreal-intermediate", "Unreal intermediate files", RulePlatform.GameEngines, "Intermediate", UnrealMarkers, "Unreal recreates it on the next build."),
        Project("unreal-ddc", "Unreal project derived data", RulePlatform.GameEngines, "DerivedDataCache", UnrealMarkers, "Unreal rebuilds it as the editor loads assets."),
        Project("terraform", "Terraform providers", RulePlatform.DevTools, ".terraform", [".terraform.lock.hcl"], "terraform init recreates it."),
    ];

    private static Rule Folder(string id, string title, Tier tier, RulePlatform platform, string regenerate, params string[] patterns) =>
        new(id, title, tier, platform, new FolderTarget(patterns), regenerate);

    private static Rule FolderSet(
        string id, string title, Tier tier, RulePlatform platform, string regenerate, string[] patterns,
        string[]? guard = null, RulePick pick = RulePick.All, int? minAgeDays = null) =>
        new(id, title, tier, platform, new FolderTarget(patterns), regenerate)
        {
            ProcessGuard = guard ?? [],
            Pick = pick,
            MinAgeDays = minAgeDays,
        };

    private static Rule Electron(string id, string title, RulePlatform platform, string folder, string[] caches, params string[] extra) =>
        new(id, title, Tier.Safe, platform, new FolderTarget([.. caches.Select(cache => $"%ROAMING%/{folder}/{cache}"), .. extra]), "The app rebuilds its caches and writes new logs.")
        {
            SkipsRunningApps = true,
        };

    private static Rule Project(string id, string title, RulePlatform platform, string directory, string[] markers, string regenerate, string? proof = null) =>
        new($"project.{id}", title, Tier.Review, platform, new ProjectTarget(directory, markers, proof), regenerate);
}
