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
    private LiveFeed<LargeFile>? _feed;
    private DateTime _lastSort;
    private bool _initialized;

    public LargeFilesViewModel(AppServices services)
    {
        _services = services;
        Location = new ScanLocation(services, "largeFiles");
        Location.Changed += () => _ = StartScanAsync();
        Files = [];
        StatusText = "Scan drives for large files.";
        ScanButtonLabel = "Scan";
        SelectedMinSizeIndex = 1;
        SelectedAgeIndex = 0;
        _initialized = true;
    }

    public ScanLocation Location { get; }
    public ScanStatus Status { get; } = new();

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsBusy))]
    public partial bool IsScanning { get; set; }

    [ObservableProperty]
    public partial bool HasScanned { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsBusy))]
    public partial bool IsCleaning { get; set; }

    // Files listed while scanning can be picked, but cleaning waits for the scan to finish.
    public bool IsBusy => IsScanning || IsCleaning;

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
        Status.Reset("Scanning for large files...");
        StatusText = "Scanning...";
        var minBytes = MinSizeValues[Math.Clamp(SelectedMinSizeIndex, 0, MinSizeValues.Length - 1)];
        var minAge = AgeValues[Math.Clamp(SelectedAgeIndex, 0, AgeValues.Length - 1)];
        var options = new LargeFileOptions
        {
            MinBytes = minBytes,
            MinAgeDays = minAge,
            ExcludedPaths = _services.Settings.ExcludedPaths,
            Roots = Location.Scope,
        };
        _lastSort = DateTime.UtcNow;
        _feed = new LiveFeed<LargeFile>(ApplyFeed);

        try
        {
            var found = await _services.LargeFileFinder.RunAsync(options, _feed, ct);
            if (ct.IsCancellationRequested) return;
            StopFeed();
            // The finished list is the final word; choices made while scanning carry over.
            var chosen = _rawFiles.ToDictionary(f => f.FullPath, f => f.IsSelected, PathTools.Comparer);
            _rawFiles.Clear();
            foreach (var file in found)
            {
                _rawFiles.Add(new LargeFileRowViewModel(file, UpdateCounts) { IsSelected = chosen.GetValueOrDefault(file.Path) });
            }
            IsScanning = false;
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
            StopFeed();
            IsScanning = false;
            UpdateCounts();
        }
    }

    private void StopFeed()
    {
        // Cleared first, so the last batch re-sorts the list straight away.
        var feed = _feed;
        _feed = null;
        feed?.Stop();
    }

    private void ApplyFeed(IReadOnlyList<LargeFile> found, ScanUpdate<LargeFile>? latest)
    {
        foreach (var file in found) _rawFiles.Add(new LargeFileRowViewModel(file, UpdateCounts));
        Status.Update(latest?.Path, latest?.Fraction);
        Status.SetFound(_rawFiles.Count, _rawFiles.Sum(f => f.Bytes), "file(s)");
        if (found.Count == 0) return;
        if (_feed is null || DateTime.UtcNow - _lastSort >= TimeSpan.FromSeconds(1))
        {
            _lastSort = DateTime.UtcNow;
            ApplySort();
        }
    }

    [RelayCommand]
    public void CancelScan()
    {
        StopFeed();
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
