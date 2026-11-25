using DevDuster.Core.Scan;

namespace DevDuster.Core.Relocate;

internal sealed class TreeSnapshot
{
    private readonly record struct Entry(bool IsDirectory, long Size, DateTime ModifiedUtc, string? LinkTarget);

    private readonly Dictionary<string, Entry> _entries = new(StringComparer.Ordinal);

    private TreeSnapshot() { }

    public static TreeSnapshot Of(string root, CancellationToken cancellation)
    {
        var snapshot = new TreeSnapshot();
        var pending = new Stack<string>([root]);
        while (pending.TryPop(out var folder))
        {
            cancellation.ThrowIfCancellationRequested();
            var children = PathTools.TryChildren(folder) ?? throw new RelocationException($"{folder} can't be read. Nothing was moved.");
            foreach (var child in children)
            {
                var isDirectory = child is DirectoryInfo;
                var isLink = child.Attributes.HasFlag(FileAttributes.ReparsePoint);
                if (isLink && child.LinkTarget is null) throw new RelocationException($"{child.FullName} is a cloud file or mount point, which can't be moved.");
                if (child.Attributes.HasFlag(FileAttributes.Encrypted)) throw new RelocationException($"{child.FullName} is encrypted, so it can't be moved safely.");
                var size = child is FileInfo file && !isLink ? file.Length : 0;
                snapshot._entries[Path.GetRelativePath(root, child.FullName)] = new Entry(isDirectory, size, child.LastWriteTimeUtc, isLink ? child.LinkTarget : null);
                if (isDirectory && !isLink) pending.Push(child.FullName);
            }
        }
        return snapshot;
    }

    public string? FirstDifference(TreeSnapshot other)
    {
        foreach (var (path, entry) in _entries)
        {
            if (!other._entries.TryGetValue(path, out var copied)) return path;
            // Folder times change as files are added, so only what the tools read is compared.
            var isFile = !entry.IsDirectory && entry.LinkTarget is null;
            if (copied.IsDirectory != entry.IsDirectory || copied.LinkTarget != entry.LinkTarget || copied.Size != entry.Size) return path;
            if (isFile && copied.ModifiedUtc != entry.ModifiedUtc) return path;
        }
        return other._entries.Keys.FirstOrDefault(path => !_entries.ContainsKey(path));
    }
}
