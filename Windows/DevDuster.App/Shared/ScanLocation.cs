using CommunityToolkit.Mvvm.ComponentModel;
using DevDuster.Core.Scan;

namespace DevDuster.App.Shared;

// Path is null for "everywhere": the profile and every drive.
public sealed record LocationOption(string Label, string? Path);

// The drive or folder a tool scans, remembered per tool in settings when the user asks.
public sealed partial class ScanLocation : ObservableObject
{
    private const string Everywhere = "*";

    private readonly AppServices _services;
    private readonly string _key;
    private readonly bool _offersEverywhere;
    private string? _customFolder;
    private bool _loading;

    public ScanLocation(AppServices services, string key, bool offersEverywhere = true)
    {
        _services = services;
        _key = key;
        _offersEverywhere = offersEverywhere;
        Options = [];
        _loading = true;
        var remembered = services.Settings.RememberedLocations.TryGetValue(key, out var saved) ? saved : null;
        Remember = remembered is not null;
        Reload();
        if (remembered is { } path && path != Everywhere && IndexOf(path) < 0 && Directory.Exists(path))
        {
            _customFolder = path;
            Reload();
        }
        // A remembered drive that is gone falls back to the first option.
        SelectedIndex = remembered is null ? 0 : Math.Max(0, remembered == Everywhere ? Options.ToList().FindIndex(option => option.Path is null) : IndexOf(remembered));
        _loading = false;
    }

    // Raised when the user picks another location.
    public event Action? Changed;

    [ObservableProperty]
    public partial IReadOnlyList<LocationOption> Options { get; set; }

    [ObservableProperty]
    public partial int SelectedIndex { get; set; }

    [ObservableProperty]
    public partial bool Remember { get; set; }

    public LocationOption Selected => Options.Count == 0 ? new LocationOption("Everywhere", null) : Options[Math.Clamp(SelectedIndex, 0, Options.Count - 1)];

    public IReadOnlyList<string>? Scope => Selected.Path is { } path ? [path] : null;

    // Picks up drives plugged in or removed since the page opened.
    public void Refresh() => Reload();

    public void SetCustomFolder(string folder)
    {
        _customFolder = folder;
        Reload();
        SelectedIndex = Options.Count - 1;
    }

    partial void OnSelectedIndexChanged(int value)
    {
        if (_loading || value < 0) return;
        Save();
        Changed?.Invoke();
    }

    partial void OnRememberChanged(bool value)
    {
        if (!_loading) Save();
    }

    private int IndexOf(string path) => Options.ToList().FindIndex(option => option.Path is { } candidate && PathTools.IsSame(PathTools.Normalize(candidate), PathTools.Normalize(path)));

    private void Reload()
    {
        var previous = _loading;
        _loading = true;
        var list = new List<LocationOption>();
        if (_offersEverywhere) list.Add(new LocationOption("Everywhere", null));
        // The system drive comes first, as it holds most of what a developer installs.
        foreach (var drive in _services.Drives.Drives().OrderByDescending(drive => drive.IsSystem))
        {
            var label = string.IsNullOrWhiteSpace(drive.Label) ? drive.Root : $"{drive.Label} ({drive.Root.TrimEnd(Path.DirectorySeparatorChar)})";
            list.Add(new LocationOption(label, drive.Root));
        }
        list.Add(new LocationOption("Home (~)", _services.Folders.Home));
        if (_customFolder is not null) list.Add(new LocationOption(Path.GetFileName(_customFolder) is { Length: > 0 } name ? name : _customFolder, _customFolder));
        // The choice follows its path, so a drive plugged in above it does not change what is selected.
        var keep = Options.Count == 0 ? null : Selected;
        Options = list;
        var index = keep is null ? -1 : list.FindIndex(option => option.Path is null ? keep.Path is null : keep.Path is not null && PathTools.IsSame(option.Path, keep.Path));
        SelectedIndex = Math.Max(0, index);
        _loading = previous;
    }

    private void Save()
    {
        var saved = _services.Settings.RememberedLocations;
        if (Remember) saved[_key] = Selected.Path ?? Everywhere;
        else saved.Remove(_key);
        _services.SettingsStore.Save(_services.Settings);
    }
}
