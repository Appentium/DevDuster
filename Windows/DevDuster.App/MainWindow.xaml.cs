using DevDuster.App.Cleaner;
using DevDuster.App.Dashboard;
using DevDuster.App.DeveloperTools;
using DevDuster.App.DiskMap;
using DevDuster.App.LargeFiles;
using DevDuster.App.MoveTools;
using DevDuster.App.Projects;
using DevDuster.App.Settings;
using DevDuster.App.SystemCleanup;
using DevDuster.App.Uninstaller;
using DevDuster.Core.Settings;
using H.NotifyIcon;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace DevDuster.App;

public sealed partial class MainWindow : Window
{
    private readonly AppServices _services;
    private readonly LowSpaceAlerts _alerts;
    private readonly TrayIconController _tray;
    private object? _pendingNavParam;
    private bool _isExiting;

    public MainWindow(AppServices services)
    {
        _services = services;
        InitializeComponent();
        SystemBackdrop = new MicaBackdrop();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        ApplyTheme(services.Settings.Theme);
        services.ThemeChanged += OnThemeChanged;
        services.NavigationRequested += OnNavigationRequested;
        services.RecoveryFailed += OnRecoveryFailed;
        if (services.RecoveryError is { } recoveryError) ShowRecoveryError(recoveryError);
        NavView.SelectedItem = NavView.MenuItems[0];
        _alerts = new LowSpaceAlerts(services);
        _alerts.Start();
        _tray = new TrayIconController(services, DispatcherQueue, ShowFromTray, ScanNow, Quit);
        AppWindow.Closing += OnAppWindowClosing;
        Closed += (_, _) => _tray.Dispose();
    }

    public void ShowFromTray()
    {
        this.Show();
        Activate();
    }

    private void ScanNow()
    {
        ShowFromTray();
        if (ContentFrame.Content is CleanerPage cleaner)
        {
            cleaner.StartScanIfIdle();
            return;
        }
        NavigateByTag("cleaner", "scan");
    }

    private void Quit()
    {
        _isExiting = true;
        _tray.Dispose();
        Close();
    }

    private void OnAppWindowClosing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (!_isExiting && _services.Settings.TrayEnabled)
        {
            args.Cancel = true;
            this.Hide();
        }
    }

    private void OnThemeChanged(AppThemeChoice theme) =>
        DispatcherQueue.TryEnqueue(() => ApplyTheme(theme));

    private void ApplyTheme(AppThemeChoice theme)
    {
        RootGrid.RequestedTheme = theme switch
        {
            AppThemeChoice.Light => ElementTheme.Light,
            AppThemeChoice.Dark => ElementTheme.Dark,
            _ => ElementTheme.Default,
        };
    }

    private void OnRecoveryFailed(string error) =>
        DispatcherQueue.TryEnqueue(() => ShowRecoveryError(error));

    private void ShowRecoveryError(string error)
    {
        RecoveryBanner.Message = error;
        RecoveryBanner.IsOpen = true;
    }

    private void OnNavigationRequested(string tag, object? parameter) =>
        DispatcherQueue.TryEnqueue(() => NavigateByTag(tag, parameter));

    private void NavigateByTag(string tag, object? parameter)
    {
        if (tag == "settings")
        {
            _pendingNavParam = parameter;
            NavView.SelectedItem = NavView.SettingsItem;
            return;
        }
        foreach (var item in NavView.MenuItems.OfType<NavigationViewItem>())
        {
            if (Equals(item.Tag, tag))
            {
                _pendingNavParam = parameter;
                if (Equals(NavView.SelectedItem, item))
                {
                    _pendingNavParam = null;
                    ContentFrame.Navigate(PageTypeFor(tag), parameter);
                }
                else
                {
                    NavView.SelectedItem = item;
                }
                return;
            }
        }
    }

    private void OnNavSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        var parameter = _pendingNavParam;
        _pendingNavParam = null;
        if (args.IsSettingsSelected)
        {
            ContentFrame.Navigate(typeof(SettingsPage), parameter);
            return;
        }
        if (args.SelectedItem is NavigationViewItem { Tag: string tag })
        {
            ContentFrame.Navigate(PageTypeFor(tag), parameter);
        }
    }

    private static Type PageTypeFor(string tag) => tag switch
    {
        "dashboard" => typeof(DashboardPage),
        "cleaner" => typeof(CleanerPage),
        "uninstaller" => typeof(UninstallerPage),
        "projects" => typeof(ProjectsPage),
        "largefiles" => typeof(LargeFilesPage),
        "devtools" => typeof(DeveloperToolsPage),
        "movetools" => typeof(MoveToolsPage),
        "diskmap" => typeof(DiskMapPage),
        "system" => typeof(SystemCleanupPage),
        _ => typeof(DashboardPage),
    };
}
