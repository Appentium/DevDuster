using DevDuster.Core.Clean;
using DevDuster.Core.Explore;
using DevDuster.Core.Relocate;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;
using DevDuster.Core.Settings;
using DevDuster.Platform;

namespace DevDuster.App;

public sealed class AppServices
{
    public AppServices()
    {
        Folders = UserFolders.Current();
        Catalog = new RuleCatalog(Folders);
        Drives = new DriveService();
        Measure = new WindowsFileMeasure();
        Remover = new RecycleBinRemover();
        Processes = new SystemProcessProbe();
        Docker = new Docker(Folders);
        CleanLog = new CleanLog(Folders);
        Cleaner = new Core.Clean.Cleaner(Catalog, Remover, Measure, CleanLog, Docker);
        Scanner = new DusterScanner(Catalog, Drives, Measure, Processes, Docker);
        ProjectScanner = new ProjectScanner(Catalog, Drives, Measure);
        LargeFileFinder = new LargeFileFinder(Folders, Drives, Measure);
        DiskMapBuilder = new DiskMapBuilder(Measure);
        DevStorageAnalyzer = new DevStorageAnalyzer(Folders, DevToolCatalog.BuiltIn, Measure);
        RelocationCatalog = new RelocationCatalog(Folders, DevToolCatalog.BuiltIn, DevStorageAnalyzer);
        JunctionMaker = new JunctionMaker();
        Relocator = new Relocator(Folders, Drives, Measure, JunctionMaker);
        SettingsStore = new SettingsStore(Folders);
        Settings = SettingsStore.Load();
        RecycleBin = new RecycleBin();
        InstalledPrograms = new InstalledPrograms();
        CleanScheduler = new CleanScheduler();
        RecoveryTask = Task.Run(RunRecovery);
    }

    public UserFolders Folders { get; }
    public RuleCatalog Catalog { get; }
    public DriveService Drives { get; }
    public IFileMeasure Measure { get; }
    public IFileRemover Remover { get; }
    public IProcessProbe Processes { get; }
    public Docker Docker { get; }
    public CleanLog CleanLog { get; }
    public Core.Clean.Cleaner Cleaner { get; }
    public DusterScanner Scanner { get; }
    public ProjectScanner ProjectScanner { get; }
    public LargeFileFinder LargeFileFinder { get; }
    public DiskMapBuilder DiskMapBuilder { get; }
    public DevStorageAnalyzer DevStorageAnalyzer { get; }
    public RelocationCatalog RelocationCatalog { get; }
    public IJunctionMaker JunctionMaker { get; }
    public Relocator Relocator { get; }
    public SettingsStore SettingsStore { get; }
    public DusterSettings Settings { get; }
    public RecycleBin RecycleBin { get; }
    public InstalledPrograms InstalledPrograms { get; }
    public CleanScheduler CleanScheduler { get; }
    public Task RecoveryTask { get; }
    public string? RecoveryError { get; private set; }
    public ScanReport? LastScanReport { get; private set; }

    public event Action<AppThemeChoice>? ThemeChanged;
    public event Action? HistoryChanged;
    public event Action? ScanReportChanged;
    public event Action<string, object?>? NavigationRequested;
    public event Action<string>? RecoveryFailed;

    public void ApplyTheme(AppThemeChoice theme)
    {
        Settings.Theme = theme;
        SettingsStore.Save(Settings);
        ThemeChanged?.Invoke(theme);
    }

    public void UpdateScanReport(ScanReport report)
    {
        LastScanReport = report;
        ScanReportChanged?.Invoke();
    }

    public void NotifyHistoryChanged() => HistoryChanged?.Invoke();

    public void RequestNavigation(string tag, object? parameter = null) => NavigationRequested?.Invoke(tag, parameter);

    private void RunRecovery()
    {
        try
        {
            Relocator.Recover();
        }
        catch (Exception error)
        {
            RecoveryError = $"Move recovery failed: {error.Message}";
            RecoveryFailed?.Invoke(RecoveryError);
        }
    }
}
