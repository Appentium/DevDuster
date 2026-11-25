using System.Text.RegularExpressions;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Rules;

public sealed record RuleExpansion(IReadOnlyList<string> All, IReadOnlyList<string> Offered);

public sealed partial class FolderRuleExpander(UserFolders folders)
{
    public RuleExpansion Expand(Rule rule)
    {
        if (rule.Target is not FolderTarget target) return new RuleExpansion([], []);
        var groups = target.Patterns.Select(pattern => new RuleGlob(folders, pattern).Matches()).ToList();
        IReadOnlyList<string> all = [.. groups.SelectMany(group => group)];
        IReadOnlyList<string> offered = rule.Pick switch
        {
            RulePick.AllButNewestVersion => [.. groups.SelectMany(OlderVersions)],
            RulePick.UnreferencedByAvds => UnreferencedImages(all),
            _ => all,
        };
        return new RuleExpansion(all, offered);
    }

    public static Version? VersionOf(string name)
    {
        var match = VersionPattern().Match(name);
        if (!match.Success) return null;
        var parts = match.Value.Split('.').Take(4).ToList();
        if (parts.Count == 1) parts.Add("0");
        return Version.TryParse(string.Join('.', parts), out var version) ? version : null;
    }

    private static IEnumerable<string> OlderVersions(IReadOnlyList<string> paths)
    {
        var versioned = paths.Select(path => (Path: path, Version: VersionOf(Path.GetFileName(path)))).Where(entry => entry.Version is not null).ToList();
        if (versioned.Count == 0) return [];
        var newest = versioned.Max(entry => entry.Version);
        return versioned.Where(entry => entry.Version != newest).Select(entry => entry.Path);
    }

    private IReadOnlyList<string> UnreferencedImages(IReadOnlyList<string> images)
    {
        var used = new HashSet<string>(PathTools.Comparer);
        foreach (var avd in AvdDirectories())
        {
            // One unreadable config means no image is offered, rather than offering one on a guess.
            if (ReadLines(Path.Combine(avd, "config.ini")) is not { } lines) return [];
            foreach (var line in lines.Where(line => line.StartsWith("image.sysdir", StringComparison.Ordinal) && line.Contains('=')))
            {
                used.Add(ImageKey(line[(line.IndexOf('=') + 1)..].Trim()));
            }
        }
        return [.. images.Where(image => !used.Contains(ImageKey(image)))];
    }

    private IEnumerable<string> AvdDirectories()
    {
        var listed = new RuleGlob(folders, "~/.android/avd/*.ini").Matches()
            .SelectMany(ini => ReadLines(ini) ?? [])
            .Where(line => line.StartsWith("path=", StringComparison.Ordinal))
            .Select(line => PathTools.Real(line["path=".Length..].Trim()))
            .OfType<string>();
        return new RuleGlob(folders, "~/.android/avd/*.avd").Matches().Concat(listed).Distinct(PathTools.Comparer);
    }

    private static string[]? ReadLines(string path)
    {
        try { return File.ReadAllLines(path); }
        catch (Exception error) when (PathTools.IsFileError(error)) { return null; }
    }

    private static string ImageKey(string path)
    {
        var normalized = path.Replace('\\', '/').TrimEnd('/');
        var start = normalized.IndexOf("system-images/", StringComparison.OrdinalIgnoreCase);
        return start < 0 ? normalized : normalized[start..];
    }

    [GeneratedRegex(@"\d+(?:\.\d+)+|\d+")]
    private static partial Regex VersionPattern();
}
