using DevDuster.Core.Scan;

namespace DevDuster.Core.Rules;

public sealed class ProjectArtifactMatcher
{
    private readonly ILookup<string, Rule> _rulesByDirectory;
    private readonly ILookup<string, string[]> _markersByName;
    private readonly HashSet<string> _markerExtensions;

    public ProjectArtifactMatcher(RuleCatalog catalog)
    {
        var rules = catalog.Rules.Where(rule => rule.Target is ProjectTarget).ToList();
        _rulesByDirectory = rules.ToLookup(rule => ((ProjectTarget)rule.Target).Directory, PathTools.Comparer);
        var markers = rules.SelectMany(rule => ((ProjectTarget)rule.Target).Markers).Distinct(PathTools.Comparer).ToList();
        _markerExtensions = [.. markers.Where(IsExtension).Select(marker => marker[1..])];
        _markersByName = markers.Where(marker => !IsExtension(marker)).Select(marker => marker.Split('/')).ToLookup(parts => parts[^1], PathTools.Comparer);
    }

    public IEnumerable<int> ProjectLevels(string filePath)
    {
        var name = Path.GetFileName(filePath);
        if (_markerExtensions.Contains(Path.GetExtension(name).ToLowerInvariant())) yield return 0;
        foreach (var parts in _markersByName[name])
        {
            // A nested marker such as ProjectSettings/ProjectVersion.txt marks the folder above its own folder.
            var tail = PathTools.Components(filePath).TakeLast(parts.Length);
            if (parts.Length == 1 || parts.SequenceEqual(tail, PathTools.Comparer)) yield return parts.Length - 1;
        }
    }

    public Rule? RuleForArtifact(string path)
    {
        var parent = Path.GetDirectoryName(path);
        if (parent is null) return null;
        return _rulesByDirectory[Path.GetFileName(path)].FirstOrDefault(rule =>
        {
            var target = (ProjectTarget)rule.Target;
            if (target.Proof is { } proof && !PathTools.Exists(Path.Combine(path, proof))) return false;
            return target.Markers.Any(marker => IsPresent(marker, parent));
        });
    }

    private static bool IsPresent(string marker, string parent) =>
        IsExtension(marker)
            ? PathTools.Children(parent).OfType<FileInfo>().Any(file => Path.GetExtension(file.Name).Equals(marker[1..], PathTools.Comparison))
            : PathTools.IsPlainFile(Path.Combine(parent, marker.Replace('/', Path.DirectorySeparatorChar)));

    private static bool IsExtension(string marker) => marker.StartsWith("*.", StringComparison.Ordinal);
}
