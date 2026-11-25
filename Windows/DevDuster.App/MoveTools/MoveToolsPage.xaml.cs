using DevDuster.App.Shared;
using DevDuster.Core.Relocate;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace DevDuster.App.MoveTools;

public sealed partial class MoveToolsPage : Page
{
    public MoveToolsPage()
    {
        ViewModel = new MoveToolsViewModel(App.Current.Services);
        InitializeComponent();
    }

    public MoveToolsViewModel ViewModel { get; }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.LoadAsync();
    }

    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        ViewModel.CancelMeasure();
    }

    private async void OnChooseDestinationClicked(object sender, RoutedEventArgs e)
    {
        if (App.Current.MainWindow is not { } window) return;
        var folder = await Ui.PickFolderAsync(window);
        if (folder is not null) ViewModel.SetPickedFolder(folder);
    }

    private async void OnMoveClicked(object sender, RoutedEventArgs e)
    {
        if (ViewModel.SelectedTarget is not { } target) return;
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"Move {target.Title}?",
            Content = $"DevDuster copies it to {ViewModel.DestinationPath}, checks every file, creates a junction at {target.Path}, then deletes the old copy. You can move it back at any time.",
            PrimaryButtonText = "Move",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            await ViewModel.MoveSelectedAsync();
        }
    }

    private async void OnMoveBackClicked(object sender, RoutedEventArgs e)
    {
        if (ViewModel.IsBusy || sender is not FrameworkElement { Tag: Relocation relocation }) return;
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"Move {relocation.Title} back?",
            Content = $"DevDuster copies it back to {relocation.Original}, verifies every file, and removes the moved copy.",
            PrimaryButtonText = "Move Back",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            await ViewModel.MoveBackAsync(relocation);
        }
    }

    private void OnRevealClicked(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string path }) Ui.RevealInExplorer(path);
    }

    private void OnRevealLeftoverClicked(object sender, RoutedEventArgs e) =>
        Ui.RevealInExplorer(ViewModel.LeftoverPath);
}
