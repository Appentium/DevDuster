using DevDuster.Core.Clean;
using DevDuster.Core.Maintenance;

// DISM exits with this when it worked but wants a restart.
const int RestartRequired = 3010;
// The only input is one of the fixed task ids; the app reads the outcome from the exit code.
if (args is not [var id] || SystemTask.All.FirstOrDefault(candidate => candidate.Id == id) is not { } task) return 2;
if (!Environment.IsPrivilegedProcess) return 2;
// Folders come from Windows itself, never from arguments or environment variables.
var maintenance = new SystemMaintenance(
    Environment.GetFolderPath(Environment.SpecialFolder.Windows), Environment.SystemDirectory,
    (executable, parameters, timeout) => CommandRunner.Run(executable, parameters, timeout, RestartRequired) is not null);
return maintenance.Run(task) ? 0 : 1;
