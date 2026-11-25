using DevDuster.Core.Rules;

namespace DevDuster.Core.Scan;

public sealed class RunningAppGuard(UserFolders folders, IReadOnlySet<string> runningNames)
{
    private readonly List<(string Key, string Name)> _running = [.. runningNames.Select(name => (Key(name), name)).Where(entry => entry.Item1.Length > 0)];

    public string? OwnerOf(ScanItem item)
    {
        if (!item.Rule.SkipsRunningApps) return null;
        var root = new[] { folders.RoamingAppData, folders.LocalAppData }.Select(path => PathTools.Real(path) ?? path).FirstOrDefault(path => PathTools.IsInside(item.Path, path));
        var components = PathTools.Components(item.Path);
        var app = Key(root is null ? components[^1] : components[PathTools.Components(root).Length]);
        // Folder and process names differ by channel suffixes, so either may prefix the other.
        return _running.FirstOrDefault(entry => entry.Key == app || IsPrefix(entry.Key, app) || IsPrefix(app, entry.Key)).Name;
    }

    private static bool IsPrefix(string prefix, string text) => prefix.Length >= 4 && text.StartsWith(prefix, StringComparison.Ordinal);

    private static string Key(string name) => string.Concat(name.Where(char.IsLetterOrDigit)).ToLowerInvariant();
}
