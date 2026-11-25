using System.Globalization;
using System.Text;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Clean;

public sealed record CleanRecord(DateTime DateUtc, long Bytes);

public sealed class CleanLog(string path)
{
    public CleanLog(UserFolders folders) : this(Path.Combine(folders.DusterData, "Logs", "clean.log")) { }

    public void Append(CleanMode mode, long bytes, string removedPath)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var line = string.Create(CultureInfo.InvariantCulture, $"{DateTime.UtcNow:O}\t{mode}\t{bytes}\t{removedPath}\n");
        // Append sharing keeps lines whole when the app and the scheduled CLI write at the same time.
        using var stream = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite);
        stream.Write(Encoding.UTF8.GetBytes(line));
    }

    public IReadOnlyList<CleanRecord> Records()
    {
        string[] lines;
        try
        {
            using var reader = new StreamReader(new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite));
            lines = reader.ReadToEnd().Split('\n');
        }
        catch (Exception error) when (PathTools.IsFileError(error)) { return []; }
        var records = new List<CleanRecord>();
        foreach (var line in lines)
        {
            var fields = line.Split('\t', 4);
            if (fields.Length == 4
                && DateTime.TryParse(fields[0], CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var date)
                && long.TryParse(fields[2], CultureInfo.InvariantCulture, out var bytes))
            {
                records.Add(new CleanRecord(date.ToUniversalTime(), bytes));
            }
        }
        return records;
    }
}
