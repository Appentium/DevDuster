using System.Windows.Input;
using CommunityToolkit.Mvvm.Input;
using DevDuster.App.Shared;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace DevDuster.App.Cleaner;

public sealed partial class CleanerPage : Page
{
    public CleanerPage()
    {
        ViewModel = new CleanerViewModel(App.Current.Services);
        CleanCommand = new AsyncRelayCommand(CleanAsync);
        InitializeComponent();
    }

    public CleanerViewModel ViewModel { get; }
    public ICommand CleanCommand { get; }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        if (Equals(e.Parameter, "scan") && !ViewModel.IsScanning)
        {
            _ = ViewModel.StartScanAsync();
        }
    }

    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        ViewModel.CancelScan();
    }

    private void OnRevealClicked(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string path }) Ui.RevealInExplorer(path);
    }

    private async Task CleanAsync()
    {
        if (ViewModel.IsCleaning) return;
        ViewModel.IsCleaning = true;
        try
        {
            var results = await CleanFlow.ExecuteAsync(App.Current.Services, XamlRoot, ViewModel.SelectedScanItems);
            if (results is not null) ViewModel.ApplyCleanResults(results);
        }
        finally
        {
            ViewModel.IsCleaning = false;
        }
    }
}
