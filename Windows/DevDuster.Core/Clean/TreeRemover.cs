using DevDuster.Core.Scan;

namespace DevDuster.Core.Clean;

public static class TreeRemover
{
    public static IReadOnlyList<string> Remove(string path)
    {
        var failures = new List<string>();
        Remove(path, failures);
        return failures;
    }

    private static bool Remove(string path, List<string> failures)
    {
        try
        {
            if (PathTools.Attributes(path) is not { } attributes) return true;
            var isDirectory = attributes.HasFlag(FileAttributes.Directory);
            if (attributes.HasFlag(FileAttributes.ReparsePoint))
            {
                // Mount points and cloud placeholders have no link target and stay untouched.
                if (PathTools.LinkTarget(path) is null) throw new IOException("Unsupported link.");
                if (isDirectory) Directory.Delete(path, recursive: false);
                else File.Delete(path);
                return true;
            }
            if (attributes.HasFlag(FileAttributes.ReadOnly)) File.SetAttributes(path, attributes & ~FileAttributes.ReadOnly);
            if (!isDirectory)
            {
                File.Delete(path);
                return true;
            }
            if (PathTools.TryChildren(path) is not { } children) throw new IOException("Unreadable folder.");
            var isEmpty = true;
            foreach (var child in children) isEmpty &= Remove(child.FullName, failures);
            if (isEmpty) Directory.Delete(path, recursive: false);
            return isEmpty;
        }
        catch (Exception error) when (PathTools.IsFileError(error))
        {
            failures.Add(path);
            return false;
        }
    }
}
