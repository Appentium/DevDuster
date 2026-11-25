using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DevDuster.App.Shared;
using DevDuster.Core.Clean;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.App.Dashboard;

public sealed record DriveCardModel(LocalDrive Drive, long RecycleBytes)
{
    public string Title => string.IsNullOrWhiteSpace(Drive.Label) ? Drive.Root : $"{Drive.Label} ({Drive.Root.TrimEnd('\\')})";
    public string FormatText => Drive.Format;
    public double UsedPercent => Drive.TotalBytes > 0 ? Math.Clamp(100.0 * Drive.UsedBytes / Drive.TotalBytes, 0, 100) : 0;
    public string SpaceSummary => $"{ByteText.Format(Drive.AvailableBytes)} free of {ByteText.Format(Drive.TotalBytes)}";
    public string RecycleText => ByteText.Format(RecycleBytes);
    public bool CanEmpty => RecycleBytes > 0;
    public string DriveTag => Drive.IsSystem ? "System" : Drive.IsRemovable ? "Removable" : "Local";
}

public sealed record WeekBarModel(string Label, long Bytes, double BarHeight, string ToolTipText)
{
    public string SizeText => Bytes > 0 ? ByteText.Format(Bytes) : "";
}

public sealed partial class DashboardViewModel : ObservableObject
{
    private readonly AppServices _services;

    public DashboardViewModel(AppServices services)
    {
        _services = services;
        Drives = [];
        WeeklyBars = [];
        LastCleanedText = "Never cleaned with DevDuster";
        ThisWeekFreedText = "0 B";
        TotalFreedText = "0 B";
        TotalRecycleText = "0 B";
        ReclaimableTotalText = "Not scanned";
        SafeReclaimableText = "0 B";
        ReviewReclaimableText = "0 B";
        CautionReclaimableText = "0 B";
    }

    [ObservableProperty]
    public partial bool IsLoading { get; set; }

    [ObservableProperty]
    public partial string? ErrorMessage { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<DriveCardModel> Drives { get; set; }

    [ObservableProperty]
    public partial string LastCleanedText { get; set; }

    [ObservableProperty]
    public partial string ThisWeekFreedText { get; set; }

    [ObservableProperty]
    public partial string TotalFreedText { get; set; }

    [ObservableProperty]
    public partial string TotalRecycleText { get; set; }

    [ObservableProperty]
    public partial IReadOnlyList<WeekBarModel> WeeklyBars { get; set; }

    [ObservableProperty]
    public partial bool HasScan { get; set; }

    [ObservableProperty]
    public partial string ReclaimableTotalText { get; set; }

    [ObservableProperty]
    public partial string SafeReclaimableText { get; set; }

    [ObservableProperty]
    public partial string ReviewReclaimableText { get; set; }

    [ObservableProperty]
    public partial string CautionReclaimableText { get; set; }

    [RelayCommand]
    public async Task RefreshAsync()
    {
        if (IsLoading) return;
        IsLoading = true;
        ErrorMessage = null;
        try
        {
            var (driveCards, history) = await Task.Run(() =>
            {
                var drives = _services.Drives.Drives();
                var cards = drives.Select(d => new DriveCardModel(d, _services.RecycleBin.BytesOn(d.Root))).ToList();
                var hist = new CleanHistory(_services.CleanLog.Records());
                return (cards, hist);
            });

            Drives = driveCards;
            TotalRecycleText = ByteText.Format(driveCards.Sum(c => c.RecycleBytes));
            LastCleanedText = history.LastCleanedUtc is { } last
                ? $"Last cleaned {Ui.RelativeTime(last)}"
                : "Never cleaned with DevDuster";
            TotalFreedText = ByteText.Format(history.TotalBytes);
            var weekly = history.WeeklyTotals(8, DateTime.UtcNow);
            var thisWeek = weekly.Count > 0 ? weekly[^1].Bytes : 0;
            ThisWeekFreedText = ByteText.Format(thisWeek);
            var max = Math.Max(1L, weekly.Select(w => w.Bytes).DefaultIfEmpty(0L).Max());
            WeeklyBars = [.. weekly.Select(w =>
            {
                var height = w.Bytes == 0 ? 4.0 : Math.Max(10.0, 110.0 * w.Bytes / max);
                var label = w.WeekStart.ToLocalTime().ToString("MM/dd");
                return new WeekBarModel(label, w.Bytes, height, $"{label}: {ByteText.Format(w.Bytes)}");
            })];
            UpdateScanSummary();
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

    public void UpdateScanSummary()
    {
        var report = _services.LastScanReport;
        if (report is null)
        {
            HasScan = false;
            ReclaimableTotalText = "Not scanned";
            SafeReclaimableText = "0 B";
            ReviewReclaimableText = "0 B";
            CautionReclaimableText = "0 B";
            return;
        }
        HasScan = true;
        ReclaimableTotalText = ByteText.Format(report.TotalBytes);
        SafeReclaimableText = ByteText.Format(report.Items.Where(i => i.Rule.Tier == Tier.Safe).Sum(i => i.Bytes));
        ReviewReclaimableText = ByteText.Format(report.Items.Where(i => i.Rule.Tier == Tier.Review).Sum(i => i.Bytes));
        CautionReclaimableText = ByteText.Format(report.Items.Where(i => i.Rule.Tier == Tier.Caution).Sum(i => i.Bytes));
    }

    public async Task EmptyRecycleBinAsync(LocalDrive drive)
    {
        ErrorMessage = null;
        try
        {
            await Task.Run(() => _services.RecycleBin.Empty(drive.Root));
            await RefreshAsync();
        }
        catch (Exception error)
        {
            ErrorMessage = error.Message;
        }
    }

    [RelayCommand]
    private void ScanJunk() => _services.RequestNavigation("cleaner", "scan");

    [RelayCommand]
    private void OpenCleaner() => _services.RequestNavigation("cleaner");
}
