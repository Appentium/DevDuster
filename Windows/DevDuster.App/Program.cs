using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;

namespace DevDuster.App;

public static class Program
{
    private const string InstanceKey = "Appentium.DevDuster.SingleInstance";

    [STAThread]
    public static int Main()
    {
        WinRT.ComWrappersSupport.InitializeComWrappers();
        var keyInstance = AppInstance.FindOrRegisterForKey(InstanceKey);
        if (!keyInstance.IsCurrent)
        {
            var activationArgs = AppInstance.GetCurrent().GetActivatedEventArgs();
            // An async Main would lose the STA thread WinUI needs, so the redirect waits on a pool thread.
            Task.Run(() => keyInstance.RedirectActivationToAsync(activationArgs).AsTask()).Wait();
            return 0;
        }

        keyInstance.Activated += OnActivated;
        Application.Start(_ =>
        {
            var context = new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread());
            SynchronizationContext.SetSynchronizationContext(context);
            _ = new App();
        });
        return 0;
    }

    private static void OnActivated(object? sender, AppActivationArguments e)
    {
        if (Application.Current is App app) app.ShowMainWindow();
    }
}
