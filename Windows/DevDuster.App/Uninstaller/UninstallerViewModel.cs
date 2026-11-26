using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DevDuster.App.Shared;
using DevDuster.Core.Scan;
using DevDuster.Core.Uninstall;
using Microsoft.UI.Xaml;

namespace DevDuster.App.Uninstaller;

public sealed record ProgramRowViewModel(InstalledProgram Program)
{
    public string Name => Program.Name;
    public string PublisherText => string.IsNullOrWhiteSpace(Program.Publisher) ? "Unknown publisher" : Program.Publisher;
    public string Subtitle => string.IsNullOrWhiteSpace(Program.Version) ? PublisherText : $"{PublisherText} · {Program.Version}";
    public long Bytes => Program.Bytes;
    public string SizeText => Program.Bytes > 0 ? ByteText.Format(Program.Bytes) : "—";
    public string? InstallLocation => Program.InstallLocation;
    public bool HasInstallLocation => !string.IsNullOrWhiteSpace(Program.InstallLocation);
}

public sealed partial class LeftoverRowViewModel(Leftover leftover, Action selectionChanged) : ObservableObject
{
    public Core.Scan.ScanItem Item => leftover.Item;
    public string Name => leftover.Item.Name;
    public string Path => leftover.Item.Path;
    public string Reason => leftover.Reason;
    public string SizeText => ByteText.Format(leftover.Item.Bytes);

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsChecked))]
    public partial bool IsSelected { get; set; }

    partial void OnIsSelectedChanged(bool value) => selectionChanged();

    public bool? IsChecked
    {
        get => IsSelected;
        set => IsSelected = value == true;
    }
}

public sealed partial class UninstallerViewModel : ObservableObject
{
    private readonly List<InstalledProgram> _uninstallStarted = [];
    private readonly AppServices _services;
    private readonly List<ProgramRowViewModel> _allPrograms = [];
    private bool _hasLoaded;

    public UninstallerViewModel(AppServices services)
    {
        _services = services;
        Programs = [];
        SearchText = "";
        CountText = "";
        Leftovers = [];
    }

    [ObservableProperty]
    public partial IReadOnlyList<LeftoverRowViewModel> Leftovers { get; set; }

    [ObservableProperty]
    public partial int SelectedCount { get; set; }

    [ObservableProperty]
    public partial long SelectedBytes { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsBusy))]
    public partial bool IsCleaning { get; set; }

    [ObservableProperty]
    public partial bool HasNoLeftovers { get; set; }

    [ObservableProperty]
    public partial bool IsLoading { get; set; }

    // The leftover search runs after the program list is shown, with its own progress strip.
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsBusy))]
    public partial bool IsSearchingLeftovers { get; set; }

    public bool IsBusy => IsSearchingLeftovers || IsCleaning;

    public ScanStatus Status { get; } = new();

    [ObservableProperty]
    public partial string SearchText { get; set; }

    [ObservableProperty]
    public partial int SelectedSortIndex { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<ProgramRowViewModel> Programs { get; set; }

    [ObservableProperty]
    public partial string CountText { get; set; }

    [ObservableProperty]
    public partial string? ErrorMessage { get; set; }

    [ObservableProperty]
    public partial bool HasPrograms { get; set; }

    partial void OnSearchTextChanged(string value) => ApplyFilterAndSort();
    partial void OnSelectedSortIndexChanged(int value) => ApplyFilterAndSort();

    public async Task LoadIfNeededAsync()
    {
        if (!_hasLoaded && !IsLoading) await RefreshAsync();
    }

    [RelayCommand]
    public async Task RefreshAsync()
    {
        if (IsLoading) return;
        IsLoading = true;
        ErrorMessage = null;
        try
        {
            var read = await Task.Run(_services.InstalledPrograms.Read);
            _allPrograms.Clear();
            _allPrograms.AddRange(read.Select(p => new ProgramRowViewModel(p)));
            _hasLoaded = true;
            ApplyFilterAndSort();
            await FindLeftoversAsync(read);
        }
        catch (Exception error)
        {
            ErrorMessage = error.Message;
        }
        finally
        {
            IsLoading = false;
        }
    }

    public async Task UninstallAsync(InstalledProgram program)
    {
        ErrorMessage = null;
        try
        {
            await Task.Run(() => _services.InstalledPrograms.Uninstall(program));
            _uninstallStarted.Add(program);
        }
        catch (Exception error)
        {
            ErrorMessage = error.Message;
        }
    }

    [RelayCommand]
    private void SelectAll()
    {
        foreach (var row in Leftovers) row.IsSelected = true;
    }

    [RelayCommand]
    private void DeselectAll()
    {
        foreach (var row in Leftovers) row.IsSelected = false;
    }

    public async Task CleanLeftoversAsync(XamlRoot xamlRoot)
    {
        if (IsCleaning) return;
        IsCleaning = true;
        try
        {
            var items = Leftovers.Where(row => row.IsSelected).Select(row => row.Item).ToList();
            var results = await CleanFlow.ExecuteAsync(_services, xamlRoot, items, note: "Check each folder first: it may hold settings or data you want to keep.");
            if (results is null) return;
            var removed = results.Where(result => result.Succeeded).Select(result => result.Item).ToHashSet();
            Leftovers = [.. Leftovers.Where(row => !removed.Contains(row.Item))];
            HasNoLeftovers = Leftovers.Count == 0;
            UpdateSelection();
        }
        finally
        {
            IsCleaning = false;
        }
    }

    private async Task FindLeftoversAsync(IReadOnlyList<InstalledProgram> listed)
    {
        // A program counts as removed only once its registry entry is gone.
        var removed = _uninstallStarted.Where(program => listed.All(other => other.Id != program.Id)).ToList();
        var finder = new LeftoverFinder(_services.Folders, _services.Measure, _services.Processes);
        var rows = new List<LeftoverRowViewModel>();
        Leftovers = [];
        HasNoLeftovers = false;
        IsSearchingLeftovers = true;
        Status.Reset("Looking for leftover folders...");
        var feed = new LiveFeed<Leftover>((found, latest) =>
        {
            rows.AddRange(found.Select(leftover => new LeftoverRowViewModel(leftover, UpdateSelection)));
            Status.Update(latest?.Path, latest?.Fraction);
            Status.SetFound(rows.Count, rows.Sum(row => row.Item.Bytes), "folder(s)");
            if (found.Count > 0) Leftovers = [.. rows.OrderByDescending(row => row.Item.Bytes)];
        });
        try
        {
            var found = await Task.Run(() => finder.Find(_services.InstalledPrograms.ReadForLeftovers(), removed, progress: feed));
            feed.Stop();
            // The finished list is the final word; choices made while searching carry over.
            var chosen = rows.Where(row => row.IsSelected).Select(row => row.Item.Path).ToHashSet(PathTools.Comparer);
            Leftovers = [.. found.Select(leftover => new LeftoverRowViewModel(leftover, UpdateSelection) { IsSelected = chosen.Contains(leftover.Item.Path) })];
        }
        finally
        {
            feed.Stop();
            IsSearchingLeftovers = false;
            HasNoLeftovers = Leftovers.Count == 0;
            UpdateSelection();
        }
    }

    private void UpdateSelection()
    {
        var selected = Leftovers.Where(row => row.IsSelected).ToList();
        SelectedCount = selected.Count;
        SelectedBytes = selected.Sum(row => row.Item.Bytes);
    }

    private void ApplyFilterAndSort()
    {
        var query = SearchText.Trim();
        IEnumerable<ProgramRowViewModel> filtered = string.IsNullOrEmpty(query)
            ? _allPrograms
            : _allPrograms.Where(p =>
                p.Name.Contains(query, StringComparison.OrdinalIgnoreCase)
                || p.PublisherText.Contains(query, StringComparison.OrdinalIgnoreCase));

        var sort = SelectedSortIndex == 1 ? SortOrder.Name : SortOrder.Size;
        var sorted = sort == SortOrder.Size
            ? filtered.OrderByDescending(p => p.Bytes).ThenBy(p => p.Name, StringComparer.CurrentCultureIgnoreCase).ToList()
            : filtered.OrderBy(p => p.Name, StringComparer.CurrentCultureIgnoreCase).ThenByDescending(p => p.Bytes).ToList();

        Programs = sorted;
        HasPrograms = sorted.Count > 0;
        CountText = $"{sorted.Count} program(s)";
    }
}
