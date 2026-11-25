using System.Windows.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DevDuster.App.Shared;

public sealed partial class FooterBar : UserControl
{
    public static readonly DependencyProperty SelectedCountProperty =
        DependencyProperty.Register(nameof(SelectedCount), typeof(int), typeof(FooterBar), new PropertyMetadata(0));

    public static readonly DependencyProperty SelectedBytesProperty =
        DependencyProperty.Register(nameof(SelectedBytes), typeof(long), typeof(FooterBar), new PropertyMetadata(0L));

    public static readonly DependencyProperty CanSelectAllProperty =
        DependencyProperty.Register(nameof(CanSelectAll), typeof(bool), typeof(FooterBar), new PropertyMetadata(false));

    public static readonly DependencyProperty CanDeselectAllProperty =
        DependencyProperty.Register(nameof(CanDeselectAll), typeof(bool), typeof(FooterBar), new PropertyMetadata(false));

    public static readonly DependencyProperty IsBusyProperty =
        DependencyProperty.Register(nameof(IsBusy), typeof(bool), typeof(FooterBar), new PropertyMetadata(false));

    public static readonly DependencyProperty ActionTitleProperty =
        DependencyProperty.Register(nameof(ActionTitle), typeof(string), typeof(FooterBar), new PropertyMetadata("Clean"));

    public static readonly DependencyProperty SelectAllCommandProperty =
        DependencyProperty.Register(nameof(SelectAllCommand), typeof(ICommand), typeof(FooterBar), new PropertyMetadata(null));

    public static readonly DependencyProperty DeselectAllCommandProperty =
        DependencyProperty.Register(nameof(DeselectAllCommand), typeof(ICommand), typeof(FooterBar), new PropertyMetadata(null));

    public static readonly DependencyProperty CleanCommandProperty =
        DependencyProperty.Register(nameof(CleanCommand), typeof(ICommand), typeof(FooterBar), new PropertyMetadata(null));

    public FooterBar()
    {
        InitializeComponent();
    }

    public int SelectedCount
    {
        get => (int)GetValue(SelectedCountProperty);
        set => SetValue(SelectedCountProperty, value);
    }

    public long SelectedBytes
    {
        get => (long)GetValue(SelectedBytesProperty);
        set => SetValue(SelectedBytesProperty, value);
    }

    public bool CanSelectAll
    {
        get => (bool)GetValue(CanSelectAllProperty);
        set => SetValue(CanSelectAllProperty, value);
    }

    public bool CanDeselectAll
    {
        get => (bool)GetValue(CanDeselectAllProperty);
        set => SetValue(CanDeselectAllProperty, value);
    }

    public bool IsBusy
    {
        get => (bool)GetValue(IsBusyProperty);
        set => SetValue(IsBusyProperty, value);
    }

    public string ActionTitle
    {
        get => (string)GetValue(ActionTitleProperty);
        set => SetValue(ActionTitleProperty, value);
    }

    public ICommand? SelectAllCommand
    {
        get => (ICommand?)GetValue(SelectAllCommandProperty);
        set => SetValue(SelectAllCommandProperty, value);
    }

    public ICommand? DeselectAllCommand
    {
        get => (ICommand?)GetValue(DeselectAllCommandProperty);
        set => SetValue(DeselectAllCommandProperty, value);
    }

    public ICommand? CleanCommand
    {
        get => (ICommand?)GetValue(CleanCommandProperty);
        set => SetValue(CleanCommandProperty, value);
    }

    private static string FormatSelection(int count, long bytes) => $"{count} selected · {ByteText.Format(bytes)}";

    private static bool CanClean(int count, bool isBusy) => count > 0 && !isBusy;
}
