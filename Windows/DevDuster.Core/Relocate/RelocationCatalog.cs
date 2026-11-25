using DevDuster.Core.Explore;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Relocate;

public sealed class RelocationCatalog(UserFolders folders, IReadOnlyList<DevTool> tools, DevStorageAnalyzer analyzer)
{
    private static readonly Dictionary<string, string> BlockedReasons = new()
    {
        ["docker"] = "Move it in Docker Desktop: Settings > Resources > Disk image location.",
        ["wsl"] = "Move a distro with wsl --manage <distro> --move <folder>.",
    };

    public IReadOnlyList<RelocationTarget> Targets() =>
        [.. tools.Select(tool => (Tool: tool, Root: analyzer.RootOf(tool))).Where(entry => entry.Root is not null)
            .Select(entry => new RelocationTarget(entry.Tool.Id, entry.Tool.Title, entry.Tool.Platform, entry.Root!, BlockedReason(entry.Tool, entry.Root!)))
            .DistinctBy(target => target.Path, PathTools.Comparer)];

    private string? BlockedReason(DevTool tool, string root)
    {
        if (BlockedReasons.TryGetValue(tool.Id, out var reason)) return reason;
        if (PathTools.IsLink(root)) return "Already a link to another folder.";
        if (!PathTools.IsInside(root, folders.Home)) return "Outside your profile. DevDuster moves your tool data, never apps or system folders.";
        if (PathTools.IsSameOrInside(root, Path.Combine(folders.LocalAppData, "Packages"))) return "A Store app's private folder, which can't be a link.";
        if (folders.CloudFolders.Any(cloud => PathTools.IsSameOrInside(root, cloud))) return "Synced by OneDrive, which doesn't follow links.";
        return null;
    }
}
