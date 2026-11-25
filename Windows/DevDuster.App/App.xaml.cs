using Microsoft.UI.Xaml;

namespace DevDuster.App;

public partial class App : Application
{
    public App()
    {
        Services = new AppServices();
        InitializeComponent();
    }

    public static new App Current => (App)Application.Current;
    public AppServices Services { get; }
    public Window? MainWindow { get; private set; }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        MainWindow = new MainWindow(Services);
        MainWindow.Activate();
    }
}
