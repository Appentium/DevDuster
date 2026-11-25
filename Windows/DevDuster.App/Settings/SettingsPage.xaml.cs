using DevDuster.App.Shared;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DevDuster.App.Settings;

public sealed partial class SettingsPage : Page
{
    public SettingsPage()
    {
        ViewModel = new SettingsViewModel(App.Current.Services);
        InitializeComponent();
    }

    public SettingsViewModel ViewModel { get; }

    private async void OnAddExcludedClicked(object sender, RoutedEventArgs e)
    {
        if (App.Current.MainWindow is not { } window) return;
        var folder = await Ui.PickFolderAsync(window);
        if (folder is not null) ViewModel.AddExcludedPath(folder);
    }

    private void OnRemoveExcludedClicked(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string path }) ViewModel.RemoveExcludedPath(path);
    }
}
