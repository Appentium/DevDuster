using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DevDuster.App.Shared;
using DevDuster.Core.Clean;
using DevDuster.Core.Explore;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;
using Microsoft.UI.Xaml.Media;

namespace DevDuster.App.DeveloperTools;

public sealed partial class DevPartViewModel : ObservableObject
{
    private readonly Action _selectionChanged;

    public DevPartViewModel(DevStoragePart part, Action selectionChanged)
    {
        Part = part;
        _selectionChanged = selectionChanged;
        KindLabel = part.Kind switch
        {
            DevPartKind.Essential => "Essential",
            DevPartKind.Cleanable when part.Tier is { } t => Ui.TierTitle(t),
            _ => "Other",
        };
        Brush = Ui.PartBrush(part.Kind, part.Tier);
        // Only Safe and Review cleanable parts can be selected for cleaning.
        IsCleanable = part.Kind == DevPartKind.Cleanable && part.Tier is Tier.Safe or Tier.Review && part.Items.Count > 0;
    }

    public DevStoragePart Part { get; }
    public string Title => Part.Title;
    public long Bytes => Part.Bytes;
    public string SizeText => ByteText.Format(Part.Bytes);
    public string KindLabel { get; }
    public Brush Brush { get; }
    public bool IsCleanable { get; }

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

public sealed record DevToolCardViewModel(
    DevToolUsage Usage,
    IReadOnlyList<DevPartViewModel> Parts,
    string ShareText)
{
    public string Title => Usage.Tool.Title;
    public string Root => Usage.Root;
    public string TotalText => ByteText.Format(Usage.TotalBytes);
}

public sealed partial class DeveloperToolsViewModel : ObservableObject
{
    private readonly AppServices _services;
    private readonly List<ScanItem> _cleanableItems = [];
    private CancellationTokenSource? _scanCts;

    public DeveloperToolsViewModel(AppServices services)
    {
        _services = services;
        Tools = [];
        ProgressText = "";
        StatusText = "Measure SDKs, toolchains, and package stores split into Safe, Review, Essential, and Other.";
        ScanButtonLabel = "Scan";
        MeasuredTotalText = "0 B";
        SafeTotalText = "0 B";
        ReviewTotalText = "0 B";
        EssentialTotalText = "0 B";
        OtherTotalText = "0 B";
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
    public partial IReadOnlyList<DevToolCardViewModel> Tools { get; set; }

    [ObservableProperty]
    public partial string MeasuredTotalText { get; set; }

    [ObservableProperty]
    public partial string SafeTotalText { get; set; }

    [ObservableProperty]
    public partial string ReviewTotalText { get; set; }

    [ObservableProperty]
    public partial string EssentialTotalText { get; set; }

    [ObservableProperty]
    public partial string OtherTotalText { get; set; }

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
        [.. Tools.SelectMany(t => t.Parts).Where(p => p.IsCleanable && p.IsSelected).SelectMany(p => p.Part.Items)];

    [RelayCommand]
    public async Task StartScanAsync()
    {
        CancelScan();
        _scanCts = new CancellationTokenSource();
        var ct = _scanCts.Token;
        IsScanning = true;
        HasResults = false;
        _cleanableItems.Clear();
        Tools = [];
        UpdateCounts();
        ProgressText = "Scanning developer tools...";
        StatusText = "Scanning...";

        var progress = new ThrottledProgress<ScanProgress>(p => ProgressText = p.Path);
        try
        {
            var options = _services.Settings.ToScanOptions();
            var report = await _services.Scanner.RunAsync(options, progress, ct);
            if (ct.IsCancellationRequested) return;
            _cleanableItems.AddRange(report.Items);
            ProgressText = "Measuring developer tool roots...";
            var usages = await _services.DevStorageAnalyzer.RunAsync(_cleanableItems, ct);
            if (ct.IsCancellationRequested) return;
            BuildCards(usages);
            HasScanned = true;
            ScanButtonLabel = "Rescan";
            StatusText = Tools.Count == 0 ? "No developer tools found." : "";
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
        foreach (var part in Tools.SelectMany(t => t.Parts).Where(p => p.IsCleanable)) part.IsSelected = true;
        UpdateCounts();
    }

    [RelayCommand]
    private void DeselectAll()
    {
        foreach (var part in Tools.SelectMany(t => t.Parts).Where(p => p.IsCleanable)) part.IsSelected = false;
        UpdateCounts();
    }

    public async Task ApplyCleanResultsAsync(IReadOnlyList<CleanResult> results)
    {
        var removed = results.Where(r => r.Succeeded).Select(r => r.Item.Path).ToHashSet(PathTools.Comparer);
        if (removed.Count == 0) return;
        _cleanableItems.RemoveAll(i => removed.Contains(i.Path));
        var usages = await _services.DevStorageAnalyzer.RunAsync(_cleanableItems, CancellationToken.None);
        BuildCards(usages);
    }

    private void BuildCards(IReadOnlyList<DevToolUsage> usages)
    {
        var total = Math.Max(1L, usages.Sum(u => u.TotalBytes));
        MeasuredTotalText = ByteText.Format(usages.Sum(u => u.TotalBytes));
        SafeTotalText = ByteText.Format(SumParts(usages, DevPartKind.Cleanable, Tier.Safe));
        ReviewTotalText = ByteText.Format(SumParts(usages, DevPartKind.Cleanable, Tier.Review));
        EssentialTotalText = ByteText.Format(SumParts(usages, DevPartKind.Essential, null));
        OtherTotalText = ByteText.Format(SumParts(usages, DevPartKind.Other, null));

        Tools = [.. usages.Select(u =>
        {
            var parts = u.Parts.Select(p => new DevPartViewModel(p, UpdateCounts)).ToList();
            var pct = 100.0 * u.TotalBytes / total;
            return new DevToolCardViewModel(u, parts, $"{pct:0.0}% of measured");
        })];
        HasResults = Tools.Count > 0;
        UpdateCounts();
    }

    private static long SumParts(IReadOnlyList<DevToolUsage> usages, DevPartKind kind, Tier? tier) =>
        usages.SelectMany(u => u.Parts)
            .Where(p => p.Kind == kind && (tier is null || p.Tier == tier))
            .Sum(p => p.Bytes);

    private void UpdateCounts()
    {
        var cleanable = Tools.SelectMany(t => t.Parts).Where(p => p.IsCleanable).ToList();
        var selected = cleanable.Where(p => p.IsSelected).SelectMany(p => p.Part.Items).ToList();
        SelectedCount = selected.Count;
        SelectedBytes = selected.Sum(i => i.Bytes);
        CanSelectAll = !IsScanning && cleanable.Count > 0 && cleanable.Any(p => !p.IsSelected);
        CanDeselectAll = !IsScanning && selected.Count > 0;
    }
}
