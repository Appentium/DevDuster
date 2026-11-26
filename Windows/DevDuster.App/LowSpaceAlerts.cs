using DevDuster.App.Shared;
using DevDuster.Core.Automation;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace DevDuster.App;

public sealed class LowSpaceAlerts
{
    private readonly AppServices _services;
    private readonly LowSpaceMonitor _monitor = new();
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMinutes(5) };

    public LowSpaceAlerts(AppServices services)
    {
        _services = services;
        _timer.Tick += async (_, _) => await CheckAsync();
    }

    public void Start()
    {
        // An unpackaged app has no manifest entry for notifications, so it registers at run time.
        if (!AppServices.IsPackaged)
        {
            try { AppNotificationManager.Default.Register(); }
            catch (Exception) { }
        }
        _timer.Start();
    }

    private async Task CheckAsync()
    {
        var settings = _services.Settings;
        if (!settings.LowSpaceAlertsEnabled) return;
        var drives = await Task.Run(_services.Drives.Drives);
        foreach (var drive in _monitor.NewlyLow(drives, settings.SystemThresholdGB, settings.OtherThresholdGB))
        {
            var alert = new AppNotificationBuilder()
                .AddText($"{drive.Root} is low on space")
                .AddText($"{ByteText.Format(drive.AvailableBytes)} free. Open DevDuster to clean caches.");
            // A failed toast must not take down the timer, which runs on the UI thread.
            try { AppNotificationManager.Default.Show(alert.BuildNotification()); }
            catch (Exception) { return; }
        }
    }
}
