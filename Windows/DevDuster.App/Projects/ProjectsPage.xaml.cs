using System.Windows.Input;
using CommunityToolkit.Mvvm.Input;
using DevDuster.App.Shared;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace DevDuster.App.Projects;

public sealed partial class ProjectsPage : Page
{
    public ProjectsPage()
    {
        ViewModel = new ProjectsViewModel(App.Current.Services);
        CleanCommand = new AsyncRelayCommand(CleanAsync);
        InitializeComponent();
    }

    public ProjectsViewModel ViewModel { get; }
    public ICommand CleanCommand { get; }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.ScanIfNeededAsync();
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
            var results = await CleanFlow.ExecuteAsync(App.Current.Services, XamlRoot, ViewModel.SelectedScanItems, progress: ViewModel.CleanProgress);
            if (results is not null) ViewModel.ApplyCleanResults(results);
        }
        finally
        {
            ViewModel.IsCleaning = false;
        }
    }
}
