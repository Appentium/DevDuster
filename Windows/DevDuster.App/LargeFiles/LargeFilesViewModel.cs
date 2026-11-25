using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DevDuster.App.Shared;
using DevDuster.Core.Clean;
using DevDuster.Core.Explore;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.App.LargeFiles;

public sealed partial class LargeFileRowViewModel : ObservableObject
{
    private readonly Action _selectionChanged;

    public LargeFileRowViewModel(LargeFile file, Action selectionChanged)
    {
        File = file;
        _selectionChanged = selectionChanged;
        DirectoryPath = Path.GetDirectoryName(file.Path) ?? "";
        ModifiedText = file.ModifiedUtc.ToLocalTime().ToString("g");
    }

    public LargeFile File { get; }
    public string Name => File.Name;
    public string FullPath => File.Path;
    public string DirectoryPath { get; }
    public long Bytes => File.Bytes;
    public string SizeText => ByteText.Format(File.Bytes);
    public string ModifiedText { get; }

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

public sealed partial class LargeFilesViewModel : ObservableObject
{
    private static readonly long[] MinSizeValues = [100_000_000, 500_000_000, 1_000_000_000, 5_000_000_000];
    private static readonly int?[] AgeValues = [null, 30, 90, 365];

    private readonly AppServices _services;
    private readonly List<LargeFileRowViewModel> _rawFiles = [];
    private CancellationTokenSource? _scanCts;
    private bool _initialized;

    public LargeFilesViewModel(AppServices services)
    {
        _services = services;
        Files = [];
        ProgressText = "";
        StatusText = "Scan drives for large files.";
        ScanButtonLabel = "Scan";
        SelectedMinSizeIndex = 1;
        SelectedAgeIndex = 0;
        _initialized = true;
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
    public partial int SelectedMinSizeIndex { get; set; }

    [ObservableProperty]
    public partial int SelectedAgeIndex { get; set; }

    [ObservableProperty]
    public partial int SelectedSortIndex { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<LargeFileRowViewModel> Files { get; set; }

    [ObservableProperty]
    public partial int SelectedCount { get; set; }

    [ObservableProperty]
    public partial long SelectedBytes { get; set; }

    [ObservableProperty]
    public partial bool CanSelectAll { get; set; }

    [ObservableProperty]
    public partial bool CanDeselectAll { get; set; }

    [ObservableProperty]
    public partial bool HasResults { get; set; }

    public IReadOnlyList<ScanItem> SelectedScanItems =>
        [.. _rawFiles.Where(f => f.IsSelected).Select(f => new ScanItem(RuleCatalog.UserSelected, f.FullPath, f.Bytes))];

    partial void OnSelectedMinSizeIndexChanged(int value)
    {
        if (_initialized) _ = StartScanAsync();
    }

    partial void OnSelectedAgeIndexChanged(int value)
    {
        if (_initialized) _ = StartScanAsync();
    }

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
        _rawFiles.Clear();
        Files = [];
        UpdateCounts();
        ProgressText = "Scanning for large files...";
        StatusText = "Scanning...";

        var progress = new ThrottledProgress<string>(path => ProgressText = path);
        var minBytes = MinSizeValues[Math.Clamp(SelectedMinSizeIndex, 0, MinSizeValues.Length - 1)];
        var minAge = AgeValues[Math.Clamp(SelectedAgeIndex, 0, AgeValues.Length - 1)];
        var options = new LargeFileOptions
        {
            MinBytes = minBytes,
            MinAgeDays = minAge,
            ExcludedPaths = _services.Settings.ExcludedPaths,
        };

        try
        {
            var found = await Task.Run(() => _services.LargeFileFinder.RunAsync(options, progress, ct), ct);
            if (ct.IsCancellationRequested) return;
            foreach (var file in found)
            {
                _rawFiles.Add(new LargeFileRowViewModel(file, UpdateCounts));
            }
            HasScanned = true;
            ScanButtonLabel = "Rescan";
            ApplySort();
            StatusText = _rawFiles.Count == 0 ? "No files matched the current size and age filters." : "";
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
        foreach (var file in _rawFiles) file.IsSelected = true;
        UpdateCounts();
    }

    [RelayCommand]
    private void DeselectAll()
    {
        foreach (var file in _rawFiles) file.IsSelected = false;
        UpdateCounts();
    }

    public void ApplyCleanResults(IReadOnlyList<CleanResult> results)
    {
        var removed = results.Where(r => r.Succeeded).Select(r => r.Item.Path).ToHashSet(PathTools.Comparer);
        if (removed.Count == 0) return;
        _rawFiles.RemoveAll(f => removed.Contains(f.FullPath));
        ApplySort();
    }

    private void ApplySort()
    {
        var sort = SelectedSortIndex == 1 ? SortOrder.Name : SortOrder.Size;
        Files = sort == SortOrder.Size
            ? [.. _rawFiles.OrderByDescending(f => f.Bytes).ThenBy(f => f.Name, StringComparer.CurrentCultureIgnoreCase)]
            : [.. _rawFiles.OrderBy(f => f.Name, StringComparer.CurrentCultureIgnoreCase).ThenByDescending(f => f.Bytes)];
        HasResults = Files.Count > 0;
        UpdateCounts();
    }

    private void UpdateCounts()
    {
        var selected = _rawFiles.Where(f => f.IsSelected).ToList();
        SelectedCount = selected.Count;
        SelectedBytes = selected.Sum(f => f.Bytes);
        CanSelectAll = !IsScanning && _rawFiles.Count > 0 && selected.Count < _rawFiles.Count;
        CanDeselectAll = !IsScanning && selected.Count > 0;
    }
}
