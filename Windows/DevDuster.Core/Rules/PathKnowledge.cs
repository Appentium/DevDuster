using System.Text.RegularExpressions;

namespace DevDuster.Core.Rules;

public enum RiskLevel { Safe, Review, Critical, Blocked }

public sealed record PathFact(string Pattern, string Title, string Usage, RiskLevel Risk, string Action);

public static class PathKnowledge
{
    // Matched against the full path with forward slashes; the first match wins.
    private static readonly PathFact[] Facts =
    [
        new(@"\.vhdx$", "Virtual disk (Docker, WSL or a VM)", "A whole file system with its images, containers and files lives inside it.", RiskLevel.Critical, "Run docker system prune, or remove a distro you no longer use with wsl --unregister."),
        new(@"/(xampp/mysql/data|laragon/data|(MySQL|MariaDB)[^/]*(/[^/]+)?/data)(/|$)", "MySQL data folder", "Every local MySQL or MariaDB database lives here. Deleting folders by hand corrupts the server.", RiskLevel.Critical, "Drop the databases you don't need."),
        new(@"/PostgreSQL/[^/]+/data(/|$)", "PostgreSQL data folder", "Every local PostgreSQL database lives here.", RiskLevel.Critical, "Drop the databases you don't need with psql."),
        new(@"/xampp$", "XAMPP", "Holds your web sites (htdocs) and every XAMPP database.", RiskLevel.Critical, "Back up htdocs and the databases, then run XAMPP's uninstaller."),
        new(@"/Android/Sdk$", "Android SDK", "Android builds and emulators need it.", RiskLevel.Review, "Remove old platforms and system images in the SDK Manager."),
        new(@"/\.android/avd(/|$)", "Android emulators", "Virtual devices and the data inside them.", RiskLevel.Review, "Delete unused devices in the Device Manager."),
        new(@"/(\.ollama/models|\.lmstudio/models|huggingface/hub)$", "AI model weights", "Local models; downloading them again can take hours.", RiskLevel.Review, "Remove models you no longer run from the tool that downloaded them."),
        new(@"/steamapps$", "Steam library", "Installed games.", RiskLevel.Review, "Uninstall games in Steam."),
        new(@"/Windows\.old$", "Previous Windows installation", "Needed only to roll back the last upgrade.", RiskLevel.Blocked, "Remove it in Settings > System > Storage > Temporary files."),
        new(@"/hiberfil\.sys$", "Hibernation file", "Windows needs it for hibernate and fast startup.", RiskLevel.Blocked, "Run powercfg /hibernate off from an administrator terminal."),
        new(@"/pagefile\.sys$", "Page file", "Windows virtual memory.", RiskLevel.Blocked, "Change its size in System Properties > Performance."),
        new(@"/node_modules$", "Node packages", "Installed dependencies of one project.", RiskLevel.Safe, "npm install brings them back."),
    ];

    private static readonly (PathFact Fact, Regex Pattern)[] Compiled =
        [.. Facts.Select(fact => (fact, new Regex(fact.Pattern, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)))];

    public static PathFact? Match(string path)
    {
        var slashed = path.Replace('\\', '/');
        return Compiled.FirstOrDefault(entry => entry.Pattern.IsMatch(slashed)).Fact;
    }
}
