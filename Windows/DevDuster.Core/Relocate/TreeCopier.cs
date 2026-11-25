using DevDuster.Core.Scan;

namespace DevDuster.Core.Relocate;

internal sealed class TreeCopier(IJunctionMaker junctions, long totalBytes, IProgress<double>? progress, CancellationToken cancellation)
{
    private const int BufferSize = 1 << 20;
    private const FileAttributes KeptAttributes = FileAttributes.ReadOnly | FileAttributes.Hidden | FileAttributes.System | FileAttributes.Archive;

    private readonly byte[] _buffer = new byte[BufferSize];
    private long _copiedBytes;

    public void Copy(string source, string target)
    {
        cancellation.ThrowIfCancellationRequested();
        Directory.CreateDirectory(target);
        var children = PathTools.TryChildren(source) ?? throw new RelocationException($"{source} can't be read. Nothing was moved.");
        foreach (var child in children)
        {
            var destination = Path.Combine(target, child.Name);
            if (child.Attributes.HasFlag(FileAttributes.ReparsePoint)) CopyLink(child, destination);
            else if (child is FileInfo file) CopyFile(file, destination);
            else Copy(child.FullName, destination);
        }
        File.SetAttributes(target, (File.GetAttributes(source) & KeptAttributes) | FileAttributes.Directory);
    }

    private void CopyLink(FileSystemInfo link, string destination)
    {
        var target = link.LinkTarget ?? throw new RelocationException($"{link.FullName} can't be copied.");
        if (link is FileInfo) File.CreateSymbolicLink(destination, target);
        else if (Path.IsPathFullyQualified(target)) junctions.Create(destination, target);
        else Directory.CreateSymbolicLink(destination, target);
    }

    private void CopyFile(FileInfo file, string destination)
    {
        using (var input = new FileStream(file.FullName, FileMode.Open, FileAccess.Read, FileShare.Read))
        using (var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None))
        {
            int read;
            while ((read = input.Read(_buffer)) > 0)
            {
                cancellation.ThrowIfCancellationRequested();
                output.Write(_buffer.AsSpan(0, read));
                _copiedBytes += read;
            }
            output.Flush(flushToDisk: true);
        }
        File.SetLastWriteTimeUtc(destination, file.LastWriteTimeUtc);
        var kept = file.Attributes & KeptAttributes;
        File.SetAttributes(destination, kept == 0 ? FileAttributes.Normal : kept);
        progress?.Report(Math.Min(1, (double)_copiedBytes / Math.Max(1, totalBytes)));
    }
}
