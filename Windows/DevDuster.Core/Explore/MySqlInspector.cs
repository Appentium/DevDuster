using DevDuster.Core.Clean;

namespace DevDuster.Core.Explore;

public sealed record MySqlDatabase(string Name, long Bytes);

public sealed class MySqlInspector(Func<IReadOnlyList<string>, TimeSpan, string?> run)
{
    private static readonly string[] SystemDatabases = ["mysql", "sys", "information_schema", "performance_schema", "phpmyadmin"];
    private static readonly TimeSpan QueryTimeout = TimeSpan.FromMinutes(2);
    private static readonly TimeSpan DropTimeout = TimeSpan.FromMinutes(10);

    private const string ListQuery =
        "SELECT s.schema_name, COALESCE(SUM(t.data_length + t.index_length), 0) FROM information_schema.schemata s " +
        "LEFT JOIN information_schema.tables t ON t.table_schema = s.schema_name GROUP BY s.schema_name";

    // Only known install folders are searched, never PATH.
    public static string? FindClient(IEnumerable<string> programFolders, string systemDrive)
    {
        var candidates = new List<string>();
        var parents = programFolders.SelectMany(folder => new[] { Path.Combine(folder, "MySQL"), folder })
            .Append(Path.Combine(systemDrive, "laragon", "bin", "mysql"));
        foreach (var parent in parents.Where(Directory.Exists))
        {
            candidates.AddRange(Scan.PathTools.Children(parent)
                .Where(child => child.Name.StartsWith("MySQL", StringComparison.OrdinalIgnoreCase) || child.Name.StartsWith("MariaDB", StringComparison.OrdinalIgnoreCase))
                .Select(child => Path.Combine(child.FullName, "bin")));
        }
        // Other accounts can write under the drive root, so Program Files installs win.
        candidates.Add(Path.Combine(systemDrive, "xampp", "mysql", "bin"));
        return candidates.Select(folder => Path.Combine(folder, "mysql.exe")).FirstOrDefault(File.Exists);
    }

    public static MySqlInspector ForClient(string client) =>
        new((arguments, timeout) => CommandRunner.Run(client, arguments, timeout));

    public IReadOnlyList<MySqlDatabase>? Databases() => Execute(ListQuery, QueryTimeout) is { } output ? Parse(output) : null;

    public static IReadOnlyList<MySqlDatabase> Parse(string output) =>
        [.. output.Split('\n').Select(line => line.TrimEnd('\r').Split('\t'))
            .Where(fields => fields.Length == 2 && CanDrop(fields[0]))
            .Select(fields => new MySqlDatabase(fields[0], long.TryParse(fields[1], out var bytes) ? bytes : 0))
            .OrderByDescending(database => database.Bytes)];

    public static string DropStatement(string name) => $"DROP DATABASE `{name.Replace("`", "``")}`";

    public bool Drop(string name) => CanDrop(name) && Execute(DropStatement(name), DropTimeout) is not null;

    public void PurgeBinaryLogs() => Execute("PURGE BINARY LOGS BEFORE NOW()", QueryTimeout);

    // The client reads backslash sequences as its own commands, so such names are never sent.
    private static bool CanDrop(string name) =>
        name.Length > 0 && !name.Contains('\\') && !name.Any(char.IsControl) && !SystemDatabases.Contains(name, StringComparer.OrdinalIgnoreCase);

    // --no-defaults must come first: option files can load plugins or point the drop at another server.
    private string? Execute(string statement, TimeSpan timeout) =>
        run(["--no-defaults", "--host=127.0.0.1", "--port=3306", "--protocol=TCP", "--user=root", "--batch", "--skip-column-names", "--execute", statement], timeout);
}
