using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DevDuster.App.Shared;
using DevDuster.Platform;

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

public sealed partial class UninstallerViewModel : ObservableObject
{
    private readonly AppServices _services;
    private readonly List<ProgramRowViewModel> _allPrograms = [];
    private bool _hasLoaded;

    public UninstallerViewModel(AppServices services)
    {
        _services = services;
        Programs = [];
        SearchText = "";
        CountText = "";
    }

    [ObservableProperty]
    public partial bool IsLoading { get; set; }

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
        }
        catch (Exception error)
        {
            ErrorMessage = error.Message;
        }
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
