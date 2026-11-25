using DevDuster.Core.Clean;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;
using DevDuster.Platform;

namespace DevDuster.Cli;

public static class Program
{
    public static int Main(string[] args)
    {
        using var cancellation = new CancellationTokenSource();
        Console.CancelKeyPress += (_, eventArgs) =>
        {
            eventArgs.Cancel = true;
            cancellation.Cancel();
        };
        if (args.Length == 0) return Usage("");
        try
        {
            return args[0] switch
            {
                "scan" => ScanCommand.Run(args[1..], cancellation.Token),
                "clean" => CleanCommand.Run(args[1..], cancellation.Token),
                "dig" => DigCommand.Run(args[1..], cancellation.Token),
                _ => Usage($"Unknown command '{args[0]}'."),
            };
        }
        catch (OperationCanceledException) { return 0; }
    }

    internal static DusterScanner BuildScanner(RuleCatalog catalog, UserFolders folders) =>
        new(catalog, new DriveService(), new WindowsFileMeasure(), new SystemProcessProbe(), new Docker(folders));

    internal static Cleaner BuildCleaner(RuleCatalog catalog, UserFolders folders) =>
        new(catalog, new RecycleBinRemover(), new WindowsFileMeasure(), new CleanLog(folders), new Docker(folders));

    internal static int Usage(string message)
    {
        if (message.Length > 0) Console.Error.WriteLine(message);
        Console.Error.WriteLine("Usage:");
        Console.Error.WriteLine("  duster scan [--json] [--tier safe|review|caution]");
        Console.Error.WriteLine("  duster clean [--delete] [--yes]");
        Console.Error.WriteLine("  duster dig [path]");
        return 2;
    }
}