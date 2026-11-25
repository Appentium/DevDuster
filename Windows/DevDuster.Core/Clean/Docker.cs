using System.Globalization;
using System.Text.RegularExpressions;
using DevDuster.Core.Rules;

namespace DevDuster.Core.Clean;

public sealed partial class Docker
{
    private readonly string? _executable;

    public Docker(UserFolders folders)
    {
        DataPath = Path.Combine(folders.LocalAppData, "Docker");
        // Only Docker's own install folder is trusted, never whatever docker.exe is first on PATH.
        _executable = folders.SystemFolders.Select(folder => Path.Combine(folder, "Docker", "Docker", "resources", "bin", "docker.exe")).FirstOrDefault(File.Exists);
    }

    public string DataPath { get; }

    public long? ReclaimableBytes()
    {
        if (_executable is null) return null;
        var output = CommandRunner.Run(_executable, ["system", "df", "--format", "{{.Type}}\t{{.Reclaimable}}"], TimeSpan.FromSeconds(30));
        if (output is null) return null;
        // prune -f never touches tagged images or volumes, so only these two types count.
        return output.Split('\n').Select(line => line.Trim().Split('\t'))
            .Where(fields => fields is ["Containers" or "Build Cache", _])
            .Sum(fields => BytesIn(fields[1]) ?? 0);
    }

    public long? Prune()
    {
        if (_executable is null) return null;
        var output = CommandRunner.Run(_executable, ["system", "prune", "-f"], TimeSpan.FromMinutes(10));
        if (output is null) return null;
        var summary = output.Split('\n').FirstOrDefault(line => line.StartsWith("Total reclaimed space:", StringComparison.Ordinal));
        return summary is null ? 0 : BytesIn(summary) ?? 0;
    }

    public static long? BytesIn(string text)
    {
        var match = AmountPattern().Match(text);
        if (!match.Success) return null;
        var value = double.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture);
        var scale = match.Groups[2].Value.ToUpperInvariant() switch { "KB" => 1e3, "MB" => 1e6, "GB" => 1e9, "TB" => 1e12, _ => 1 };
        return (long)(value * scale);
    }

    [GeneratedRegex(@"(\d+(?:\.\d+)?)\s*([kKMGT]?B)")]
    private static partial Regex AmountPattern();
}
