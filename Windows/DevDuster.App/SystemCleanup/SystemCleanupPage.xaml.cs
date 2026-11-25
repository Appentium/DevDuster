using DevDuster.Core.Maintenance;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace DevDuster.App.SystemCleanup;

public sealed partial class SystemCleanupPage : Page
{
    public SystemCleanupPage()
    {
        ViewModel = new SystemCleanupViewModel(App.Current.Services);
        InitializeComponent();
    }

    public SystemCleanupViewModel ViewModel { get; }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.MeasureAsync();
    }

    private async void OnRunClicked(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: SystemTask task } || ViewModel.IsRunning) return;
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"Clean {task.Title}?",
            Content = $"{task.Detail} Files are deleted permanently. Windows asks for administrator approval next.",
            PrimaryButtonText = "Continue",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary) await ViewModel.RunAsync(task);
    }
}
