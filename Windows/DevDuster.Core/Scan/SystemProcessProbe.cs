using System.Diagnostics;

namespace DevDuster.Core.Scan;

public sealed class SystemProcessProbe : IProcessProbe
{
    public IReadOnlySet<string> RunningNames()
    {
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var process in Process.GetProcesses())
        {
            using (process)
            {
                try { names.Add(process.ProcessName); }
                catch (InvalidOperationException) { continue; }
            }
        }
        return names;
    }
}
