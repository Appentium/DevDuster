using System.Windows.Input;
using CommunityToolkit.Mvvm.Input;
using DevDuster.App.Shared;
using DevDuster.Core.Uninstall;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace DevDuster.App.Uninstaller;

public sealed partial class UninstallerPage : Page
{
    public UninstallerPage()
    {
        ViewModel = new UninstallerViewModel(App.Current.Services);
        RemoveLeftoversCommand = new AsyncRelayCommand(() => ViewModel.CleanLeftoversAsync(XamlRoot));
        InitializeComponent();
    }

    public UninstallerViewModel ViewModel { get; }
    public ICommand RemoveLeftoversCommand { get; }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.LoadIfNeededAsync();
    }

    private void OnRevealClicked(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string path }) Ui.RevealInExplorer(path);
    }

    private async void OnUninstallClicked(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: InstalledProgram program }) return;
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"Uninstall {program.Name}?",
            Content = $"Runs the vendor's uninstaller for {program.Name}.",
            PrimaryButtonText = "Uninstall",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            await ViewModel.UninstallAsync(program);
        }
    }
}
