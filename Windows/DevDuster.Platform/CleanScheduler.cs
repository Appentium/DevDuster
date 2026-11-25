using DevDuster.Core.Clean;
using DevDuster.Core.Settings;

namespace DevDuster.Platform;

public sealed class CleanScheduler
{
    private const string TaskName = @"DevDuster\Safe clean";
    private static readonly string Executable = Path.Combine(Environment.SystemDirectory, "schtasks.exe");
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(30);

    public void Apply(DusterSettings settings, string cliPath)
    {
        if (!settings.ScheduledCleanEnabled)
        {
            // A missing task also fails here, and that is the state wanted.
            CommandRunner.Run(Executable, ["/Delete", "/TN", TaskName, "/F"], Timeout);
            return;
        }
        var action = $"\"{cliPath}\" clean --yes{(settings.ScheduledCleanRecycles ? "" : " --delete")}";
        List<string> arguments = ["/Create", "/F", "/TN", TaskName, "/TR", action, "/ST", $"{settings.ScheduleHour:00}:00", "/RL", "LIMITED"];
        arguments.AddRange(settings.ScheduleFrequency == ScheduleFrequency.Weekly
            ? ["/SC", "WEEKLY", "/D", settings.ScheduleWeekday.ToString()[..3].ToUpperInvariant()]
            : ["/SC", "DAILY"]);
        if (CommandRunner.Run(Executable, arguments, Timeout) is null) throw new IOException("Windows couldn't save the scheduled clean.");
    }
}
