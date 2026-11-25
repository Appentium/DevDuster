using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace DevDuster.App.Dashboard;

public sealed partial class DashboardPage : Page
{
    public DashboardPage()
    {
        ViewModel = new DashboardViewModel(App.Current.Services);
        InitializeComponent();
        App.Current.Services.HistoryChanged += OnExternalChanged;
        App.Current.Services.ScanReportChanged += OnScanReportChanged;
    }

    public DashboardViewModel ViewModel { get; }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.RefreshAsync();
    }

    private void OnExternalChanged() =>
        DispatcherQueue.TryEnqueue(() => _ = ViewModel.RefreshAsync());

    private void OnScanReportChanged() =>
        DispatcherQueue.TryEnqueue(ViewModel.UpdateScanSummary);

    private async void OnEmptyRecycleBinClicked(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: DriveCardModel card }) return;
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"Empty Recycle Bin on {card.Drive.Root}?",
            Content = "Items in this drive's Recycle Bin will be permanently deleted. This cannot be undone.",
            PrimaryButtonText = "Empty Recycle Bin",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            await ViewModel.EmptyRecycleBinAsync(card.Drive);
        }
    }
}
