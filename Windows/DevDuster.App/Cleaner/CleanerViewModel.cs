using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DevDuster.App.Shared;
using DevDuster.Core.Clean;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.App.Cleaner;

public sealed partial class RuleGroupViewModel : ObservableObject
{
    private readonly Action _selectionChanged;
    private readonly Action<string, bool> _expandedChanged;

    public RuleGroupViewModel(Rule rule, IReadOnlyList<SelectableItem> items, Action selectionChanged, bool isExpanded, Action<string, bool> expandedChanged)
    {
        Rule = rule;
        Items = items;
        _selectionChanged = selectionChanged;
        _expandedChanged = expandedChanged;
        IsExpanded = isExpanded;
        TotalBytes = items.Sum(i => i.Bytes);
        foreach (var item in items)
        {
            item.PropertyChanged += (_, args) =>
            {
                if (args.PropertyName == nameof(SelectableItem.IsSelected))
                {
                    OnPropertyChanged(nameof(IsChecked));
                    _selectionChanged();
                }
            };
        }
    }

    public Rule Rule { get; }
    public string Title => Rule.Title;
    public string Regenerate => Rule.Regenerate;
    public IReadOnlyList<SelectableItem> Items { get; }
    public long TotalBytes { get; }
    public string SizeText => ByteText.Format(TotalBytes);

    // Kept by the page, because the list is rebuilt while a scan adds items.
    [ObservableProperty]
    public partial bool IsExpanded { get; set; }

    partial void OnIsExpandedChanged(bool value) => _expandedChanged(Rule.Id, value);

    public bool? IsChecked
    {
        get
        {
            var selected = Items.Count(i => i.IsSelected);
            if (selected == 0) return false;
            return selected == Items.Count ? true : null;
        }
        set
        {
            // The checkbox echoes the state it was just given back here; only a real click changes it.
            if (value == IsChecked) return;
            var target = value ?? false;
            foreach (var item in Items) item.IsSelected = target;
            OnPropertyChanged(nameof(IsChecked));
            _selectionChanged();
        }
    }
}

public sealed record TierSectionViewModel(Tier Tier, IReadOnlyList<RuleGroupViewModel> Rules)
{
    public string Title => Ui.TierTitle(Tier);
    public long TotalBytes => Rules.Sum(r => r.TotalBytes);
    public string SizeText => ByteText.Format(TotalBytes);
    public Microsoft.UI.Xaml.Media.Brush BadgeForeground => Ui.TierBrush(Tier);
    public Microsoft.UI.Xaml.Media.Brush BadgeBackground => Ui.TierBackgroundBrush(Tier);
}

public sealed record SkippedRuleDisplay(string Title, string Reason);

public sealed record SkippedItemDisplay(string Message, string Path);

public sealed partial class CleanerViewModel : ObservableObject
{
    private static readonly TimeSpan RebuildInterval = TimeSpan.FromSeconds(1);

    private readonly AppServices _services;
    private readonly HashSet<string> _expandedRules = [];
    private LiveFeed<ScanItem>? _feed;
    private DateTime _lastRebuild;
    private readonly List<SelectableItem> _allItems = [];
    private IReadOnlyList<SkippedRule> _rawSkippedRules = [];
    private IReadOnlyList<SkippedItem> _rawSkippedItems = [];
    private CancellationTokenSource? _scanCts;

    public CleanerViewModel(AppServices services)
    {
        _services = services;
        Location = new ScanLocation(services, "cleaner");
        Location.Changed += () => _ = StartScanAsync();
        Sections = [];
        SkippedRules = [];
        SkippedItems = [];
        StatusText = "Scan your profile and drives for caches, logs, and stale build outputs.";
        ScanButtonLabel = "Scan";
        CleanProgress.Starting += item =>
            CleanRows.MarkDeleting(_allItems, row => PathTools.Comparer.Equals(row.Path, item!.Path), item);
        CleanProgress.Finished += ApplyCleanResults;
    }

    public CleanProgress CleanProgress { get; } = new();

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsBusy))]
    public partial bool IsScanning { get; set; }

    [ObservableProperty]
    public partial bool HasScanned { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsBusy))]
    public partial bool IsCleaning { get; set; }

    // Items listed while scanning can be picked, but cleaning waits for the scan to finish.
    public bool IsBusy => IsScanning || IsCleaning;

    public ScanLocation Location { get; }
    public ScanStatus Status { get; } = new();

    [ObservableProperty]
    public partial string StatusText { get; set; }

    [ObservableProperty]
    public partial string ScanButtonLabel { get; set; }

    [ObservableProperty]
    public partial int SelectedSortIndex { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<TierSectionViewModel> Sections { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<SkippedRuleDisplay> SkippedRules { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<SkippedItemDisplay> SkippedItems { get; set; }

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

    [ObservableProperty]
    public partial bool HasSkipped { get; set; }

    public IReadOnlyList<ScanItem> SelectedScanItems => [.. _allItems.Where(i => i.IsSelected).Select(i => i.Item)];

    partial void OnSelectedSortIndexChanged(int value) => RebuildGroups();

    [RelayCommand]
    public async Task StartScanAsync()
    {
        CancelScan();
        _scanCts = new CancellationTokenSource();
        var ct = _scanCts.Token;
        IsScanning = true;
        HasScanned = false;
        HasResults = false;
        HasSkipped = false;
        _allItems.Clear();
        Sections = [];
        SkippedRules = [];
        SkippedItems = [];
        UpdateCounts();
        Status.Reset("Starting scan...");
        StatusText = "Scanning...";
        _lastRebuild = DateTime.UtcNow;
        _feed = new LiveFeed<ScanItem>(ApplyFeed);
        var feed = _feed;
        var progress = new ActionProgress<ScanProgress>(p => feed.Report(new ScanUpdate<ScanItem>($"{PhaseText(p.Phase)}: {p.Path}", p.Fraction, p.Found)));

        try
        {
            var options = _services.Settings.ToScanOptions(scope: Location.Scope);
            var report = await _services.Scanner.RunAsync(options, progress, ct);
            if (ct.IsCancellationRequested) return;
            StopFeed();
            // The report is the final word; choices made while scanning carry over.
            var chosen = _allItems.ToDictionary(item => item.Path, item => item.IsSelected, PathTools.Comparer);
            _allItems.Clear();
            _allItems.AddRange(report.Items.Select(item => new SelectableItem(item, chosen.TryGetValue(item.Path, out var selected) ? selected : item.Rule.Tier == Tier.Safe)));
            _rawSkippedRules = report.Skipped;
            _rawSkippedItems = report.SkippedItems;
            SkippedRules = [.. report.Skipped.Select(s => new SkippedRuleDisplay(s.Rule.Title, $"Skipped while {s.RunningProcess} is running"))];
            SkippedItems = [.. report.SkippedItems.Select(s => new SkippedItemDisplay($"Quit {s.RunningApp} to clean {ByteText.Format(s.Item.Bytes)}", s.Item.Path))];
            HasSkipped = SkippedRules.Count > 0 || SkippedItems.Count > 0;
            HasScanned = true;
            ScanButtonLabel = "Rescan";
            IsScanning = false;
            _services.UpdateScanReport(report);
            RebuildGroups();
            StatusText = _allItems.Count == 0 ? "No reclaimable items matched the built-in rules." : "";
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

    private static string PhaseText(ScanPhase phase) => phase switch
    {
        ScanPhase.Rules => "Checking caches",
        ScanPhase.Projects => "Searching projects",
        _ => "Measuring",
    };

    private void StopFeed()
    {
        // Cleared first, so the last batch rebuilds the list straight away.
        var feed = _feed;
        _feed = null;
        feed?.Stop();
    }

    private void ApplyFeed(IReadOnlyList<ScanItem> found, ScanUpdate<ScanItem>? latest)
    {
        foreach (var item in found) _allItems.Add(new SelectableItem(item, item.Rule.Tier == Tier.Safe));
        Status.Update(latest?.Path, latest?.Fraction);
        Status.SetFound(_allItems.Count, _allItems.Sum(i => i.Bytes));
        if (found.Count == 0) return;
        if (_feed is null || DateTime.UtcNow - _lastRebuild >= RebuildInterval)
        {
            _lastRebuild = DateTime.UtcNow;
            RebuildGroups();
        }
        else
        {
            UpdateCounts();
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
        foreach (var item in _allItems) item.IsSelected = true;
        UpdateCounts();
    }

    [RelayCommand]
    private void DeselectAll()
    {
        foreach (var item in _allItems) item.IsSelected = false;
        UpdateCounts();
    }

    public void ApplyCleanResults(IReadOnlyList<CleanResult> results)
    {
        var removed = results.Where(r => r.Succeeded).Select(r => r.Item.Path).ToHashSet(PathTools.Comparer);
        if (removed.Count == 0) return;
        _allItems.RemoveAll(i => removed.Contains(i.Path));
        _services.UpdateScanReport(new ScanReport([.. _allItems.Select(i => i.Item)], _rawSkippedRules, _rawSkippedItems));
        RebuildGroups();
    }

    private void RebuildGroups()
    {
        var sort = SelectedSortIndex == 1 ? SortOrder.Name : SortOrder.Size;
        var built = new List<TierSectionViewModel>();
        foreach (var tier in Enum.GetValues<Tier>())
        {
            var groups = _allItems
                .Where(i => i.Tier == tier)
                .GroupBy(i => i.Item.Rule.Id)
                .Select(g =>
                {
                    var sortedItems = sort == SortOrder.Size
                        ? g.OrderByDescending(i => i.Bytes).ThenBy(i => i.Name, StringComparer.CurrentCultureIgnoreCase).ToList()
                        : g.OrderBy(i => i.Name, StringComparer.CurrentCultureIgnoreCase).ThenByDescending(i => i.Bytes).ToList();
                    var rule = g.First().Item.Rule;
                    return new RuleGroupViewModel(rule, sortedItems, UpdateCounts, _expandedRules.Contains(rule.Id), OnRuleExpanded);
                });
            var sortedGroups = sort == SortOrder.Size
                ? groups.OrderByDescending(g => g.TotalBytes).ThenBy(g => g.Title, StringComparer.CurrentCultureIgnoreCase).ToList()
                : groups.OrderBy(g => g.Title, StringComparer.CurrentCultureIgnoreCase).ThenByDescending(g => g.TotalBytes).ToList();
            if (sortedGroups.Count > 0) built.Add(new TierSectionViewModel(tier, sortedGroups));
        }
        Sections = built;
        HasResults = built.Count > 0 || HasSkipped;
        UpdateCounts();
    }

    private void OnRuleExpanded(string ruleId, bool expanded)
    {
        if (expanded) _expandedRules.Add(ruleId);
        else _expandedRules.Remove(ruleId);
    }

    private void UpdateCounts()
    {
        var selected = _allItems.Where(i => i.IsSelected).ToList();
        SelectedCount = selected.Count;
        SelectedBytes = selected.Sum(i => i.Bytes);
        CanSelectAll = !IsScanning && _allItems.Count > 0 && selected.Count < _allItems.Count;
        CanDeselectAll = !IsScanning && selected.Count > 0;
    }
}
