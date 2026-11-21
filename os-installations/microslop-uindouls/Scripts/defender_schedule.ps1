#Requires -RunAsAdministrator
# Run defender_scan.ps1 on the 1st of every month at 12:00, in a pwsh window
# of the current user. If the computer is off then, it runs at the next
# chance. The Schedule.Service COM API is used because the ScheduledTasks
# module has no monthly trigger.
$name = 'Defender monthly scan'
$script = Join-Path -Path $PSScriptRoot -ChildPath 'defender_scan.ps1'
$user = "${env:USERDOMAIN}\${env:USERNAME}"
$start = (Get-Date -Day 1 -Hour 12 -Minute 0 -Second 0).AddMonths(1)

$service = New-Object -ComObject Schedule.Service
$service.Connect()
$task = $service.NewTask(0)
$task.Settings.StartWhenAvailable = $true
$task.Principal.UserId = $user
$task.Principal.LogonType = 3 # interactive: the window is visible
$task.Principal.RunLevel = 1 # highest privileges

$trigger = $task.Triggers.Create(4) # monthly
$trigger.DaysOfMonth = 1 # bit mask: day 1
$trigger.MonthsOfYear = 0xFFF # bit mask: all 12 months
$trigger.StartBoundary = $start.ToString('s')

$action = $task.Actions.Create(0) # run a program
$action.Path = 'pwsh.exe'
$action.Arguments = "-NoProfile -File `"${script}`""

# 6 = create or update; 3 = interactive token, no password stored
$folder = $service.GetFolder('\')
$null = $folder.RegisterTaskDefinition($name, $task, 6, $user, $null, 3)
Write-Output "Task '${name}' registered. First run: ${start}"
