using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DevDuster.App.Shared;

public sealed partial class ScanProgressPanel : UserControl
{
    public static readonly DependencyProperty StatusProperty =
        DependencyProperty.Register(nameof(Status), typeof(ScanStatus), typeof(ScanProgressPanel), new PropertyMetadata(null));

    public ScanProgressPanel()
    {
        InitializeComponent();
    }

    public ScanStatus Status
    {
        get => (ScanStatus)GetValue(StatusProperty);
        set => SetValue(StatusProperty, value);
    }
}
