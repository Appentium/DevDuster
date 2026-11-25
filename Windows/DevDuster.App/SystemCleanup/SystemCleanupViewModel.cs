using CommunityToolkit.Mvvm.ComponentModel;
using DevDuster.App.Shared;
using DevDuster.Core.Clean;
using DevDuster.Core.Maintenance;
using DevDuster.Core.Scan;
using DevDuster.Platform;

namespace DevDuster.App.SystemCleanup;

public sealed partial class SystemTaskViewModel : ObservableObject
{
    public SystemTaskViewModel(SystemTask task)
    {
        Task = task;
        SizeText = "";
    }

    public SystemTask Task { get; }
    public string Title => Task.Title;
    public string Detail => Task.Detail;

    [ObservableProperty]
    public partial string SizeText { get; set; }
}

public sealed partial class SystemCleanupViewModel : ObservableObject
{
    private readonly AppServices _services;

    public SystemCleanupViewModel(AppServices services)
    {
        _services = services;
        Tasks = [.. SystemTask.All.Select(task => new SystemTaskViewModel(task))];
        StatusMessage = "";
    }

    public IReadOnlyList<SystemTaskViewModel> Tasks { get; }

    [ObservableProperty]
    public partial bool IsRunning { get; set; }

    [ObservableProperty]
    public partial string StatusMessage { get; set; }

    public async Task MeasureAsync()
    {
        foreach (var row in Tasks)
        {
            var bytes = await System.Threading.Tasks.Task.Run(() => Measure(row.Task));
            // Some system folders can't be read without admin rights, so zero is not shown as a size.
            row.SizeText = bytes > 0 ? ByteText.Format(bytes) : "—";
        }
    }

    public async Task RunAsync(SystemTask task)
    {
        if (IsRunning) return;
        IsRunning = true;
        StatusMessage = $"{task.Title}: running. This can take a long time.";
        try
        {
            var before = SystemDriveFree();
            var exitCode = await System.Threading.Tasks.Task.Run(() => ElevatedHelper.Run(task));
            if (exitCode is null)
            {
                StatusMessage = "Cancelled.";
                return;
            }
            var freed = Math.Max(0, SystemDriveFree() - before);
            if (exitCode is 0 or 1)
            {
                _services.CleanLog.Append(CleanMode.Delete, freed, $"system: {task.Id}");
                _services.NotifyHistoryChanged();
            }
            StatusMessage = exitCode switch
            {
                0 => $"{task.Title}: done, {ByteText.Format(freed)} freed.",
                1 => $"{task.Title}: {ByteText.Format(freed)} freed; some items were in use and left.",
                _ => $"{task.Title} failed.",
            };
            await MeasureAsync();
        }
        catch (Exception error) when (PathTools.IsFileError(error))
        {
            StatusMessage = error.Message;
        }
        finally
        {
            IsRunning = false;
        }
    }

    private long SystemDriveFree() => _services.Drives.Drives().FirstOrDefault(drive => drive.IsSystem)?.AvailableBytes ?? 0;

    private long Measure(SystemTask task)
    {
        var maintenance = new SystemMaintenance(
            Environment.GetFolderPath(Environment.SpecialFolder.Windows), Environment.SystemDirectory, (_, _, _) => false);
        var sizes = new SizeCalculator(_services.Measure);
        return maintenance.Targets(task).Sum(target => sizes.AllocatedSize(target));
    }
}
