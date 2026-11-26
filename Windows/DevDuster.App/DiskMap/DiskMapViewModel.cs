using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DevDuster.App.Shared;
using DevDuster.Core.Explore;
using DevDuster.Core.Scan;

namespace DevDuster.App.DiskMap;

public sealed record BreadcrumbEntry(int Index, string Name);

public sealed record InsightRow(Insight Insight)
{
    public string Heading => $"{Insight.Title} · {ByteText.Format(Insight.Bytes)}";
    public string Path => Insight.Path;
    public string Explanation => $"{Insight.Reason} {Insight.Action}";
}

public sealed partial class DiskMapViewModel : ObservableObject
{
    private static readonly long[] MinSizeValues = [0, 1_000_000, 10_000_000, 100_000_000, 1_000_000_000];

    private readonly AppServices _services;
    private readonly List<DiskNode> _trail = [];
    private DiskNode? _rootNode;
    private CancellationTokenSource? _scanCts;
    public DiskMapViewModel(AppServices services)
    {
        _services = services;
        // The map needs one folder, so "everywhere" is not offered here.
        Location = new ScanLocation(services, "diskMap", offersEverywhere: false);
        Location.Changed += () => _ = StartScanAsync();
        Trail = [];
        ExcludedPaths = [];
        UnreadablePaths = [];
        Insights = [];
        ProgressText = "";
        StatusText = "Ready";
        CurrentSizeText = "";
        UnreadableText = "";
        EmptyMessage = "";
        SelectedMinSizeIndex = 0;
    }

    public event Action? TreemapChanged;

    [ObservableProperty]
    public partial bool IsScanning { get; set; }

    [ObservableProperty]
    public partial bool HasScanned { get; set; }

    [ObservableProperty]
    public partial string ProgressText { get; set; }

    [ObservableProperty]
    public partial string StatusText { get; set; }

    [ObservableProperty]
    public partial string CurrentSizeText { get; set; }

    [ObservableProperty]
    public partial string UnreadableText { get; set; }

    [ObservableProperty]
    public partial bool HasUnreadable { get; set; }

    [ObservableProperty]
    public partial bool CanNavigateUp { get; set; }

    [ObservableProperty]
    public partial bool HasTreemap { get; set; }

    [ObservableProperty]
    public partial string EmptyMessage { get; set; }

    public ScanLocation Location { get; }

    [ObservableProperty]
    public partial int SelectedMinSizeIndex { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<BreadcrumbEntry> Trail { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<string> UnreadablePaths { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<InsightRow> Insights { get; set; }

    [ObservableProperty]
    public partial bool HasInsights { get; set; }

    [ObservableProperty]
    public partial DiskNode? SelectedNode { get; set; }

    [ObservableProperty]
    public partial bool CanRevealSelected { get; set; }

    [ObservableProperty]
    public partial bool CanDeleteSelected { get; set; }

    [ObservableProperty]
    public partial bool HasExcluded { get; set; }

    public ObservableCollection<string> ExcludedPaths { get; }

    public IReadOnlyList<DiskNode> VisibleChildren { get; private set; } = [];

    partial void OnSelectedMinSizeIndexChanged(int value) => UpdateCurrentView();

    partial void OnSelectedNodeChanged(DiskNode? value)
    {
        var valid = value is not null && value.FoldedCount == 0 && !string.IsNullOrEmpty(value.Path);
        CanRevealSelected = valid;
        CanDeleteSelected = valid;
    }

    public async Task ScanIfNeededAsync()
    {
        if (!HasScanned && !IsScanning) await StartScanAsync();
    }

    [RelayCommand]
    public async Task StartScanAsync()
    {
        if (Location.Selected.Path is not { } targetPath) return;
        CancelScan();
        _scanCts = new CancellationTokenSource();
        var ct = _scanCts.Token;
        var target = Location.Selected;

        IsScanning = true;
        _rootNode = null;
        _trail.Clear();
        Trail = [];
        VisibleChildren = [];
        SelectedNode = null;
        UnreadablePaths = [];
        HasUnreadable = false;
        UnreadableText = "";
        Insights = [];
        HasInsights = false;
        HasTreemap = false;
        EmptyMessage = "";
        ProgressText = $"Scanning {target.Label}...";
        StatusText = $"Scanning {target.Label}...";
        TreemapChanged?.Invoke();

        var progress = new ThrottledProgress<DiskMapProgress>(p =>
            ProgressText = $"{ByteText.Format(p.BytesScanned)} across {p.ItemsScanned:N0} items · {p.Path}");

        try
        {
            var excluded = ExcludedPaths.ToList();
            var node = await Task.Run(() => _services.DiskMapBuilder.RunAsync(targetPath, excluded, progress, ct), ct);
            if (ct.IsCancellationRequested) return;
            if (node is not null && _services.Drives.DriveOf(node.Path) is { } drive) node = DiskAccounting.WithUnseen(node, drive);
            _rootNode = node;
            HasScanned = true;
            if (node is not null)
            {
                _trail.Add(node);
                UnreadablePaths = node.Unreadable;
                HasUnreadable = node.Unreadable.Count > 0;
                UnreadableText = $"Unreadable: {node.Unreadable.Count}";
                Insights = [.. node.Insights.Select(insight => new InsightRow(insight))];
                HasInsights = Insights.Count > 0;
            }
            UpdateCurrentView();
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

    public void DrillInto(DiskNode node)
    {
        if (!node.IsDirectory || node.FoldedCount > 0) return;
        _trail.Add(node);
        SelectedNode = null;
        UpdateCurrentView();
    }

    [RelayCommand]
    public void NavigateUp()
    {
        if (_trail.Count <= 1) return;
        _trail.RemoveAt(_trail.Count - 1);
        SelectedNode = null;
        UpdateCurrentView();
    }

    public void NavigateTo(int index)
    {
        if (index < 0 || index >= _trail.Count) return;
        _trail.RemoveRange(index + 1, _trail.Count - index - 1);
        SelectedNode = null;
        UpdateCurrentView();
    }

    // Stops at the deepest folder still on the map, since small ones are folded away.
    public void ShowPath(string path)
    {
        if (_trail.Count == 0) return;
        _trail.RemoveRange(1, _trail.Count - 1);
        while (_trail[^1].Children.FirstOrDefault(child =>
            child.IsDirectory && child.FoldedCount == 0 && PathTools.IsSameOrInside(path, child.Path)) is { } next)
        {
            _trail.Add(next);
        }
        SelectedNode = null;
        UpdateCurrentView();
    }

    public void Exclude(DiskNode node)
    {
        if (!node.IsDirectory || node.FoldedCount > 0) return;
        if (!ExcludedPaths.Contains(node.Path, PathTools.Comparer)) ExcludedPaths.Add(node.Path);
        HasExcluded = ExcludedPaths.Count > 0;
        RemoveNode(node);
    }

    public void IncludeAgain(string path)
    {
        ExcludedPaths.Remove(path);
        HasExcluded = ExcludedPaths.Count > 0;
    }

    public void RemoveNode(DiskNode node)
    {
        if (_rootNode is null) return;
        _rootNode = _rootNode.Removing(node.Path);
        var reconciled = new List<DiskNode> { _rootNode };
        for (var i = 1; i < _trail.Count; i++)
        {
            var targetPath = _trail[i].Path;
            var match = reconciled[^1].Children.FirstOrDefault(c => PathTools.IsSame(c.Path, targetPath));
            if (match is null) break;
            reconciled.Add(match);
        }
        _trail.Clear();
        _trail.AddRange(reconciled);
        if (SelectedNode is not null && PathTools.IsSame(SelectedNode.Path, node.Path)) SelectedNode = null;
        UpdateCurrentView();
    }

    public void SetHovered(DiskNode? node)
    {
        if (node is not null)
        {
            StatusText = node.FoldedCount > 0
                ? $"{node.Name} · {ByteText.Format(node.Bytes)}"
                : $"{node.Name} · {ByteText.Format(node.Bytes)} · {node.Path}";
            return;
        }
        if (_trail.Count > 0)
        {
            var current = _trail[^1];
            var hidden = current.Children.Count - VisibleChildren.Count;
            StatusText = hidden > 0
                ? $"{current.Children.Count} items in {current.Name} ({hidden} hidden by size filter)"
                : $"{current.Children.Count} items in {current.Name}";
        }
        else
        {
            StatusText = "Ready";
        }
    }

    private void UpdateCurrentView()
    {
        Trail = [.. _trail.Select((n, i) => new BreadcrumbEntry(i, n.Name))];
        CanNavigateUp = _trail.Count > 1;
        if (_trail.Count == 0)
        {
            CurrentSizeText = "";
            VisibleChildren = [];
            HasTreemap = false;
            EmptyMessage = HasScanned ? "Folder could not be read." : "Choose a location to scan.";
            SetHovered(null);
            TreemapChanged?.Invoke();
            return;
        }
        var current = _trail[^1];
        CurrentSizeText = ByteText.Format(current.Bytes);
        var minBytes = MinSizeValues[Math.Clamp(SelectedMinSizeIndex, 0, MinSizeValues.Length - 1)];
        VisibleChildren = [.. current.Children.Where(c => c.Bytes >= minBytes && c.Bytes > 0)];
        HasTreemap = VisibleChildren.Count > 0;
        EmptyMessage = HasTreemap
            ? ""
            : current.Children.All(c => c.Bytes == 0)
                ? $"No allocated files inside {current.Name}."
                : $"Every item in {current.Name} is smaller than {ByteText.Format(minBytes)}.";
        SetHovered(null);
        TreemapChanged?.Invoke();
    }
}
