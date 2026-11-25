using DevDuster.Core.Clean;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Tests;

public sealed class Fixture : IDisposable
{
    public string Root { get; }
    public UserFolders Folders { get; }
    public RuleCatalog Catalog { get; }
    public FakeMeasure Measure { get; } = new();
    public FakeDrives Drives { get; } = new();

    public Fixture()
    {
        var basePath = Path.Combine(Path.GetTempPath(), "DevDusterTests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(basePath);
        Root = PathTools.Real(basePath) ?? PathTools.Normalize(basePath);
        Folders = new UserFolders(
            Path.Combine(Root, "home"),
            Path.Combine(Root, "home", "AppData", "Local"),
            Path.Combine(Root, "home", "AppData", "Roaming"),
            Path.Combine(Root, "tmp"))
        {
            SystemFolders = new[] { Path.Combine(Root, "Windows"), Path.Combine(Root, "ProgramFiles") },
            CloudFolders = new[] { Path.Combine(Root, "OneDrive") },
        };
        string[] folders = [Folders.LocalAppData, Folders.RoamingAppData, Folders.Temp];
        foreach (var folder in folders) Directory.CreateDirectory(folder);
        Catalog = new RuleCatalog(Folders);
    }

    public string At(string relative) => Path.Combine([Root, .. relative.Split('/')]);

    public string MakeDirectory(string relative)
    {
        var path = At(relative);
        Directory.CreateDirectory(path);
        return path;
    }

    public string MakeFile(string relative, int bytes = 10_000, double ageDays = 0, string? text = null)
    {
        var path = At(relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        if (text is not null) File.WriteAllText(path, text);
        else File.WriteAllBytes(path, new byte[bytes]);
        Age(path, ageDays);
        return path;
    }

    public void Age(string path, double days)
    {
        var date = DateTime.UtcNow.AddDays(-days);
        File.SetLastWriteTimeUtc(path, date);
        File.SetCreationTimeUtc(path, date);
    }

    public string MakeSymlink(string relative, string target)
    {
        var path = At(relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.CreateSymbolicLink(path, target);
        return path;
    }

    public DusterScanner MakeScanner(params string[] running) =>
        new(Catalog, Drives, Measure, new FakeProcesses(running), new Docker(Folders));

    public ProjectScanner MakeProjectScanner() => new(Catalog, Drives, Measure);

    public Cleaner MakeCleaner(IFileRemover remover, CleanLog log) =>
        new(Catalog, remover, Measure, log, new Docker(Folders));

    public ScanReport Scan(ScanOptions options, params string[] running) =>
        MakeScanner(running).RunAsync(options, null, CancellationToken.None).GetAwaiter().GetResult();

    public Rule Rule(string id) => Catalog.Rules.First(rule => rule.Id == id);

    public void Dispose()
    {
        try { Directory.Delete(Root, recursive: true); }
        catch (IOException) { return; }
    }
}

public sealed class FakeMeasure : IFileMeasure
{
    private readonly Func<FileInfo, string?>? _hardLinkId;

    public FakeMeasure(Func<FileInfo, string?>? hardLinkId = null) => _hardLinkId = hardLinkId;

    public FileMeasure Measure(FileInfo file) => new(file.Length, _hardLinkId?.Invoke(file));
}

public sealed class FakeProcesses : IProcessProbe
{
    private readonly HashSet<string> _names;

    public FakeProcesses(params string[] names) => _names = new HashSet<string>(names, StringComparer.OrdinalIgnoreCase);

    public IReadOnlySet<string> RunningNames() => _names;
}

public sealed class FakeRemover : IFileRemover
{
    public List<string> Recycled { get; } = [];

    public void Recycle(string path) => Recycled.Add(path);
}

public sealed class FakeDrives : DriveService
{
    public override IReadOnlyList<LocalDrive> Drives() => [];
}