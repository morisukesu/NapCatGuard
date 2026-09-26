$ErrorActionPreference = 'Stop'

# Register the NapCat guard task:
#   - runs once right after logon
#   - then repeats every 5 minutes, forever
#   - highest privileges (launcher.bat needs admin to inject into QQ)
#
# Launch path, changed 2026-09-17 (the flashing-window fix):
#   Task Scheduler -> pythonw.exe -> _tool\silent_run.py -> powershell.exe -File napcat-guard.ps1
#
#   The old action started powershell.exe directly. Even with -WindowStyle
#   Hidden that put a window on the desktop every 2 minutes: Windows Terminal is
#   the default terminal application on this machine, so the console is handed
#   to Windows Terminal and the window belongs to Windows Terminal - powershell
#   cannot hide it. Measured with _tool\win_probe.py: the old action produced one
#   visible Windows Terminal window per run, the path below produced none.
#   pythonw.exe is GUI-subsystem, so it never allocates a console in the first
#   place, and silent_run.py starts the real command with CREATE_NO_WINDOW.
#
# Re-running this script is safe: the task is overwritten.

$TaskName    = 'NapCatGuard'
$ScriptPath  = 'D:\Astrbot\_tool\napcat-guard.ps1'
$Pythonw     = 'D:\Astrbot\AstrBot\.venv\Scripts\pythonw.exe'
$SilentRun   = 'D:\Astrbot\_tool\silent_run.py'
$IntervalMin = 5      # health-check period (was 2 minutes)

$action = New-ScheduledTaskAction `
    -Execute $Pythonw `
    -Argument ('"' + $SilentRun + '" --exe powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $ScriptPath + '"')

# trigger 1: at logon (immediate check)
$tLogon = New-ScheduledTaskTrigger -AtLogOn

# trigger 2: every $IntervalMin minutes, forever
$tRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMin) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$principal = New-ScheduledTaskPrincipal `
    -UserId ($env:USERDOMAIN + '\' + $env:USERNAME) `
    -LogonType Interactive `
    -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger @($tLogon, $tRepeat) `
    -Principal $principal `
    -Settings $settings `
    -Force | Out-Null

$task = Get-ScheduledTask -TaskName $TaskName
$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Output ('registered: ' + $task.TaskName + '  state=' + $task.State)
Write-Output ('action    : ' + $task.Actions[0].Execute + ' ' + $task.Actions[0].Arguments)
foreach ($t in $task.Triggers) {
    Write-Output ('trigger   : ' + $t.CimClass.CimClassName + '  interval=' + $t.Repetition.Interval)
}
Write-Output ('next run  : ' + $info.NextRunTime)
