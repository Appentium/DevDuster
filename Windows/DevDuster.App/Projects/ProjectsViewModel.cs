using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DevDuster.App.Shared;
using DevDuster.Core.Clean;
using DevDuster.Core.Scan;

namespace DevDuster.App.Projects;

public sealed partial class ProjectFolderViewModel : ObservableObject
{
    private readonly Action _selectionChanged;

    public ProjectFolderViewModel(string projectPath, ScanItem item, Action selectionChanged)
    {
        Item = item;
        _selectionChanged = selectionChanged;
        RelativePath = PathTools.IsInside(item.Path, projectPath)
            ? Path.GetRelativePath(projectPath, item.Path)
            : item.Name;
    }

    public ScanItem Item { get; }
    public string RelativePath { get; }
    public string FullPath => Item.Path;
    public long Bytes => Item.Bytes;
    public string SizeText => ByteText.Format(Item.Bytes);

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsChecked))]
    public partial bool IsSelected { get; set; }

    public bool? IsChecked
    {
        get => IsSelected;
        set
        {
            if (value is { } selected && selected != IsSelected) IsSelected = selected;
        }
    }

    partial void OnIsSelectedChanged(bool value) => _selectionChanged();
}

public sealed partial class ProjectGroupViewModel : ObservableObject
{
    private readonly Action _selectionChanged;

    public ProjectGroupViewModel(DevProject project, bool isStale, Action selectionChanged)
    {
        Project = project;
        IsStale = isStale;
        _selectionChanged = selectionChanged;
        var name = Path.GetFileName(project.Path);
        Name = string.IsNullOrEmpty(name) ? project.Path : name;
        PlatformsText = string.Join(", ", project.Platforms.Select(Ui.PlatformLabel));
        LastActivityText = Ui.RelativeTime(project.LastActivityUtc);
        Folders = [.. project.Folders.Select(f => new ProjectFolderViewModel(project.Path, f, OnFolderSelectionChanged))];
    }

    public DevProject Project { get; }
    public string Name { get; }
    public string FullPath => Project.Path;
    public string PlatformsText { get; }
    public string LastActivityText { get; }
    public bool IsStale { get; }
    public List<ProjectFolderViewModel> Folders { get; }
    public long TotalBytes => Folders.Sum(f => f.Bytes);
    public string SizeText => ByteText.Format(TotalBytes);

    public bool? IsChecked
    {
        get
        {
            var selected = Folders.Count(f => f.IsSelected);
            if (selected == 0) return false;
            return selected == Folders.Count ? true : null;
        }
        set
        {
            var target = value ?? false;
            foreach (var folder in Folders) folder.IsSelected = target;
            OnPropertyChanged(nameof(IsChecked));
            _selectionChanged();
        }
    }

    public void RefreshBytes() => OnPropertyChanged(nameof(SizeText));

    private void OnFolderSelectionChanged()
    {
        OnPropertyChanged(nameof(IsChecked));
        _selectionChanged();
    }
}

public sealed partial class ProjectsViewModel : ObservableObject
{
    private readonly AppServices _services;
    private readonly List<ProjectGroupViewModel> _rawProjects = [];
    private CancellationTokenSource? _scanCts;

    public ProjectsViewModel(AppServices services)
    {
        _services = services;
        Projects = [];
        ProgressText = "";
        StatusText = "Scan for projects with build outputs or dependency folders.";
        ScanButtonLabel = "Scan";
    }

    [ObservableProperty]
    public partial bool IsScanning { get; set; }

    [ObservableProperty]
    public partial bool HasScanned { get; set; }

    [ObservableProperty]
    public partial bool IsCleaning { get; set; }

    [ObservableProperty]
    public partial string ProgressText { get; set; }

    [ObservableProperty]
    public partial string StatusText { get; set; }

    [ObservableProperty]
    public partial string ScanButtonLabel { get; set; }

    [ObservableProperty]
    public partial int SelectedSortIndex { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<ProjectGroupViewModel> Projects { get; set; }

    [ObservableProperty]
    public partial int SelectedCount { get; set; }

    [ObservableProperty]
    public partial long SelectedBytes { get; set; }

    [ObservableProperty]
    public partial bool CanSelectAll { get; set; }

    [ObservableProperty]
    public partial bool CanDeselectAll { get; set; }

    [ObservableProperty]
    public partial bool CanSelectStale { get; set; }

    [ObservableProperty]
    public partial bool HasResults { get; set; }

    public IReadOnlyList<ScanItem> SelectedScanItems =>
        [.. _rawProjects.SelectMany(p => p.Folders).Where(f => f.IsSelected).Select(f => f.Item)];

    partial void OnSelectedSortIndexChanged(int value) => ApplySort();

    public async Task ScanIfNeededAsync()
    {
        if (!HasScanned && !IsScanning) await StartScanAsync();
    }

    [RelayCommand]
    public async Task StartScanAsync()
    {
        CancelScan();
        _scanCts = new CancellationTokenSource();
        var ct = _scanCts.Token;
        IsScanning = true;
        HasResults = false;
        _rawProjects.Clear();
        Projects = [];
        UpdateCounts();
        ProgressText = "Scanning projects...";
        StatusText = "Scanning projects...";

        IProgress<string> progress = new ThrottledProgress<string>(path => ProgressText = path);
        try
        {
            var options = _services.Settings.ToScanOptions();
            var scanned = await _services.ProjectScanner.ScanAsync(options, path => progress.Report(path), ct);
            if (ct.IsCancellationRequested) return;
            foreach (var project in scanned)
            {
                _rawProjects.Add(new ProjectGroupViewModel(project, options.IsStale(project.LastActivityUtc), UpdateCounts));
            }
            HasScanned = true;
            ScanButtonLabel = "Rescan";
            ApplySort();
            StatusText = _rawProjects.Count == 0 ? "No projects with build output or dependency folders were found." : "";
        }
        catch (OperationCanceledException)
        {
            StatusText = "Scan cancelled.";
        }
        finally
        {
            IsScanning = false;
            ProgressText = "";
        }
    }

    [RelayCommand]
    public void CancelScan()
    {
        _scanCts?.Cancel();
        _scanCts?.Dispose();
        _scanCts = null;
        IsScanning = false;
    }

    [RelayCommand]
    private void SelectAll()
    {
        foreach (var folder in _rawProjects.SelectMany(p => p.Folders)) folder.IsSelected = true;
        UpdateCounts();
    }

    [RelayCommand]
    private void SelectStale()
    {
        foreach (var project in _rawProjects)
        {
            foreach (var folder in project.Folders) folder.IsSelected = project.IsStale;
        }
        UpdateCounts();
    }

    [RelayCommand]
    private void DeselectAll()
    {
        foreach (var folder in _rawProjects.SelectMany(p => p.Folders)) folder.IsSelected = false;
        UpdateCounts();
    }

    public void ApplyCleanResults(IReadOnlyList<CleanResult> results)
    {
        var removed = results.Where(r => r.Succeeded).Select(r => r.Item.Path).ToHashSet(PathTools.Comparer);
        if (removed.Count == 0) return;
        foreach (var project in _rawProjects)
        {
            project.Folders.RemoveAll(f => removed.Contains(f.FullPath));
            project.RefreshBytes();
        }
        _rawProjects.RemoveAll(p => p.Folders.Count == 0);
        ApplySort();
    }

    private void ApplySort()
    {
        var sort = SelectedSortIndex == 1 ? SortOrder.Name : SortOrder.Size;
        Projects = sort == SortOrder.Size
            ? [.. _rawProjects.OrderByDescending(p => p.TotalBytes).ThenBy(p => p.Name, StringComparer.CurrentCultureIgnoreCase)]
            : [.. _rawProjects.OrderBy(p => p.Name, StringComparer.CurrentCultureIgnoreCase).ThenByDescending(p => p.TotalBytes)];
        HasResults = Projects.Count > 0;
        UpdateCounts();
    }

    private void UpdateCounts()
    {
        var all = _rawProjects.SelectMany(p => p.Folders).ToList();
        var selected = all.Where(f => f.IsSelected).ToList();
        SelectedCount = selected.Count;
        SelectedBytes = selected.Sum(f => f.Bytes);
        CanSelectAll = !IsScanning && all.Count > 0 && selected.Count < all.Count;
        CanDeselectAll = !IsScanning && selected.Count > 0;
        CanSelectStale = !IsScanning && _rawProjects.Any(p => p.IsStale && p.Folders.Count > 0);
    }
}
