using System.ComponentModel;
using System.Diagnostics;
using DevDuster.Core.Maintenance;

namespace DevDuster.Platform;

public static class ElevatedHelper
{
    private const int CancelledByUser = 1223;

    // Returns null when the user dismisses the UAC prompt.
    public static int? Run(SystemTask task)
    {
        // The installed package folder is read-only to users; the execution alias is not, so never elevate that.
        var helper = Path.Combine(AppContext.BaseDirectory, "devduster-helper.exe");
        var start = new ProcessStartInfo(helper) { UseShellExecute = true, Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden };
        start.ArgumentList.Add(task.Id);
        try
        {
            using var process = Process.Start(start) ?? throw new IOException("The helper didn't start.");
            process.WaitForExit();
            return process.ExitCode;
        }
        catch (Win32Exception error) when (error.NativeErrorCode == CancelledByUser) { return null; }
        catch (Win32Exception error) { throw new IOException($"The helper couldn't start: {error.Message}", error); }
    }
}
