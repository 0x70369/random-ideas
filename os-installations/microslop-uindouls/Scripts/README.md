These are scripts I developed to improve the slopware whenever I'm forced to
use it. They work on Windows 10 and 11.

Many settings were taken from
[Chris Titus Tech's WinUtil](https://github.com/ChrisTitusTech/winutil),
others I searched throughout the web (mainly Reddit). Registry values are
checked against [Group Policy Search](https://gpsearch.azurewebsites.net).

## Before running

In an elevated PowerShell, allow local scripts and unblock the downloaded ones
(files from the internet are marked as such and stay blocked otherwise):

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Get-ChildItem -Path . -Filter *.ps1 | Unblock-File
```

Run every script from an elevated PowerShell, except
`delete_files_in_tmp.ps1`. `HKCU` settings apply to the account that runs
them. Sign out or restart afterwards.

## Scripts

| Script | What it does |
| --- | --- |
| `common.ps1` | Helper used by the `reg_*` scripts; not run directly |
| `reg_privacy.ps1` | Every data upload to Microsoft a policy can stop (telemetry, reports, sync, Recall, Copilot); Defender cloud at maximum, SmartScreen warns |
| `reg_interface.ps1` | Explorer, Start, taskbar: no suggestions, shows extensions, hidden files and seconds |
| `reg_rtc_utc.ps1` | Hardware clock in UTC, as Linux does (dual boot) |
| `reg_edge.ps1` | Edge doesn't install, update or start by itself (WebView2 still allowed) |
| `reg_ie.ps1` | Internet Explorer and Edge's IE mode off, IE component removed (restart needed) |
| `reg_windowsupdate.ps1` | Delays updates, no preview builds, installs on the 4th Saturday at 08:00 |
| `reg_windowsupdate_drivers_disable.ps1` / `_enable.ps1` | Windows Update stops or resumes installing drivers |
| `reg_hibernation_enable.ps1` / `_disable.ps1` | Hibernation on or off; fast startup always off |
| `defender_scan.ps1` | Updates Defender, scans the boot sectors and the whole system |
| `defender_schedule.ps1` | Runs `defender_scan.ps1` monthly in a visible `pwsh` window |
| `delete_files_in_tmp.ps1` | Empties `C:\tmp` |

`reg_privacy.ps1` has a commented line that hides the "Windows Backup" app.
It does so by blocking Microsoft accounts in every app and service (Store
included), so only use it with local accounts. There is no way to hide only
the icon.

`defender_schedule.ps1` needs PowerShell 7 (`pwsh`). To remove the task:
`Unregister-ScheduledTask -TaskName 'Defender monthly scan'`.

## Updating from PowerShell

From [Chris Titus Tech][ctt], using the [PSWindowsUpdate][pswu] module. Once:

```powershell
Install-Module PSWindowsUpdate
Add-WUServiceManager -MicrosoftUpdate
```

Then, whenever you want to update (`-AutoReboot` restarts when needed):

```powershell
Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot | Out-File "C:\tmp\$(Get-Date -f yyyy-MM-dd)-MSUpdates.log" -Force
```

[ctt]: https://christitus.com/install-windows-update-powershell/
[pswu]: https://www.powershellgallery.com/packages/PSWindowsUpdate
