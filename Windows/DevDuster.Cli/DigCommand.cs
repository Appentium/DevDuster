using DevDuster.Core.Explore;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;
using DevDuster.Platform;

namespace DevDuster.Cli;

internal static class DigCommand
{
    private const int TopInsights = 15;

    public static int Run(string[] args, CancellationToken cancellation)
    {
        if (args.Length > 1) return Program.Usage("dig takes at most one path.");
        var path = Path.GetFullPath(args.Length == 1 ? args[0] : UserFolders.Current().SystemDrive ?? @"C:\");
        var tree = new DiskMapBuilder(new WindowsFileMeasure()).RunAsync(path, [], null, cancellation).GetAwaiter().GetResult();
        if (tree is null)
        {
            Console.Error.WriteLine($"Couldn't read {path}.");
            return 1;
        }
        var scanned = tree.Bytes;
        if (new DriveService().DriveOf(tree.Path) is { } drive) tree = DiskAccounting.WithUnseen(tree, drive);
        Console.WriteLine($"{tree.Path}: {tree.Bytes.Size()}");
        foreach (var child in tree.Children) Console.WriteLine($"  {child.Bytes.Size(),10}  {child.Name}");
        Console.WriteLine($"Scanned: {scanned.Size()}, unreadable folders: {tree.Unreadable.Count}");
        foreach (var insight in tree.Insights.Take(TopInsights))
        {
            Console.WriteLine($"{insight.Bytes.Size(),10}  {insight.Title}: {insight.Path}");
            Console.WriteLine($"            {insight.Reason} {insight.Action}");
        }
        return 0;
    }
}
