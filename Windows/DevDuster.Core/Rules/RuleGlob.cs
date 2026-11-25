using System.IO.Enumeration;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Rules;

public sealed class RuleGlob
{
    private readonly string? _base;
    private readonly string[] _components;

    public RuleGlob(UserFolders folders, string pattern)
    {
        var slash = pattern.IndexOf('/');
        var root = folders.Resolve(slash < 0 ? pattern : pattern[..slash]);
        var parts = slash < 0 ? [] : pattern[(slash + 1)..].Split('/');
        var literalCount = Array.FindIndex(parts, IsWildcard) is var index && index >= 0 ? index : parts.Length;
        // The last component is never resolved, so a linked item is skipped instead of followed.
        var prefixCount = Math.Max(0, Math.Min(literalCount, parts.Length - 1));
        _base = PathTools.Real(parts.Take(prefixCount).Aggregate(root, Path.Combine));
        _components = parts[prefixCount..];
    }

    public IReadOnlyList<string> Matches()
    {
        if (_base is null || _components.Length == 0) return [];
        IReadOnlyList<string> current = [_base];
        for (var index = 0; index < _components.Length; index++)
        {
            var component = _components[index];
            var isLast = index == _components.Length - 1;
            current = [.. current.SelectMany(parent => Candidates(parent, component)).Where(path =>
                isLast ? PathTools.Attributes(path) is { } attributes && !attributes.HasFlag(FileAttributes.ReparsePoint) : PathTools.IsPlainDirectory(path))];
        }
        return current;
    }

    public bool Contains(string path)
    {
        if (_base is null || _components.Length == 0 || !PathTools.IsInside(path, _base)) return false;
        var parts = PathTools.Components(path)[PathTools.Components(_base).Length..];
        return parts.Length >= _components.Length && !_components.Where((pattern, index) => !IsMatch(pattern, parts[index])).Any();
    }

    private static IEnumerable<string> Candidates(string parent, string component) =>
        IsWildcard(component)
            ? PathTools.Children(parent).Where(child => IsMatch(component, child.Name)).Select(child => child.FullName)
            : [Path.Combine(parent, component)];

    private static bool IsWildcard(string component) => component.AsSpan().IndexOfAny('*', '?') >= 0;

    private static bool IsMatch(string pattern, string name)
    {
        // A leading wildcard never matches a hidden dot folder.
        if (name.StartsWith('.') && !pattern.StartsWith('.')) return false;
        return FileSystemName.MatchesSimpleExpression(pattern, name, ignoreCase: true);
    }
}
