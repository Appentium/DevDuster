namespace DevDuster.Core.Scan;

public static class PathTools
{
    private const int MaxLinkDepth = 32;

    public static StringComparison Comparison => StringComparison.OrdinalIgnoreCase;
    public static StringComparer Comparer => StringComparer.OrdinalIgnoreCase;

    // Also expands 8.3 short names of existing paths on Windows.
    public static string Normalize(string path) => Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));

    public static bool IsInside(string path, string parent)
    {
        var prefix = Path.EndsInDirectorySeparator(parent) ? parent : parent + Path.DirectorySeparatorChar;
        return path.Length > prefix.Length && path.StartsWith(prefix, Comparison);
    }

    public static bool IsSame(string left, string right) => string.Equals(left, right, Comparison);

    public static bool IsSameOrInside(string path, string parent) => IsSame(path, parent) || IsInside(path, parent);

    public static string[] Components(string path)
    {
        var root = Path.GetPathRoot(path) ?? "";
        return path[root.Length..].Split(Path.DirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries);
    }

    public static FileAttributes? Attributes(string path)
    {
        try { return File.GetAttributes(path); }
        catch (Exception error) when (IsFileError(error)) { return null; }
    }

    public static bool Exists(string path) => Attributes(path) is not null;

    public static bool IsLink(string path) => Attributes(path) is { } attributes && attributes.HasFlag(FileAttributes.ReparsePoint);

    public static bool IsPlainDirectory(string path) =>
        Attributes(path) is { } attributes && attributes.HasFlag(FileAttributes.Directory) && !attributes.HasFlag(FileAttributes.ReparsePoint);

    public static bool IsPlainFile(string path) =>
        Attributes(path) is { } attributes && !attributes.HasFlag(FileAttributes.Directory) && !attributes.HasFlag(FileAttributes.ReparsePoint);

    public static bool IsFileError(Exception error) =>
        error is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException or System.Security.SecurityException;

    public static string? LinkTarget(string path)
    {
        try { return new DirectoryInfo(path).LinkTarget; }
        catch (Exception error) when (IsFileError(error)) { return null; }
    }

    public static IReadOnlyList<FileSystemInfo> Children(string path) => TryChildren(path) ?? [];

    public static IReadOnlyList<FileSystemInfo>? TryChildren(string path)
    {
        try
        {
            return new DirectoryInfo(path).GetFileSystemInfos("*", new EnumerationOptions { AttributesToSkip = 0, IgnoreInaccessible = false });
        }
        catch (Exception error) when (IsFileError(error)) { return null; }
    }

    public static string? Real(string path) => Real(path, 0);

    public static string? RealParent(string path)
    {
        var full = Normalize(path);
        var parent = Path.GetDirectoryName(full);
        if (parent is null) return full;
        return Real(parent) is { } real ? Path.Combine(real, Path.GetFileName(full)) : null;
    }

    private static string? Real(string path, int depth)
    {
        if (depth > MaxLinkDepth) return null;
        var full = Normalize(path);
        var current = Path.GetPathRoot(full);
        if (string.IsNullOrEmpty(current)) return null;
        foreach (var component in Components(full))
        {
            var next = Path.Combine(current, component);
            if (Attributes(next) is not { } attributes) return null;
            if (attributes.HasFlag(FileAttributes.ReparsePoint) && LinkTarget(next) is { } target)
            {
                var resolved = Real(Path.IsPathRooted(target) ? target : Path.Combine(current, target), depth + 1);
                if (resolved is null) return null;
                current = resolved;
            }
            else
            {
                current = next;
            }
        }
        return current;
    }
}
