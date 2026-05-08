@echo off

:: This script removes everything inside a folder of your choice,
:: simply edit the path to it (create the folder first).

:: Its purpose is to make the chosen folder work as /tmp on Linux,
:: i.e. a temporary folder, but separate from the system's
:: temp folders as to avoid any problems.

:: It's meant to be run at shutdown time through Group Policy, but it could
:: also be run via a scheduled task (useful for non-Pro editions).
:: If you decide to run via Group Policy, the folder below is recommended:
:: C:\Windows\System32\GroupPolicy\Machine\Scripts\Shutdown

:: NOTE: This folder will only exist after you perform the steps below:
:: 1. Run "gpedit.msc" as admin;
:: 2. Go to Local Computer Policy > Computer Configuration > Windows Settings
:: > Scripts (Startup/Shutdown) > Shutdown > Add > Add a Script > Browse.
:: 3. Close the File Explorer window that just opened.

:: Now you can save the script inside the folder. Follow theses steps again
:: to add the script to the list that will run at shutdown.
:: Please test the script by saving >>>unimportant data<<< and rebooting!

del /f /q /s "C:\tmp\*.*"

for /d %%x in ("C:\tmp\*") do rmdir /s /q "%%x"
