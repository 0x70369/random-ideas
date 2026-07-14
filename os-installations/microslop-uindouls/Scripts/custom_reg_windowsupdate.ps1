# Check if the script is running with administrator privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "====================================================================" -ForegroundColor Red
    Write-Host "==   This script needs to be run with administrator privileges.   ==" -ForegroundColor Red
    Write-Host "==    Please open an elevated PowerShell prompt and try again.    ==" -ForegroundColor Red
    Write-Host "====================================================================" -ForegroundColor Red
    exit
}

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Function to add a registry key
function Set-RegistryKey {
    param (
        [string]$path,
        [string]$name,
        [string]$type,
        [string]$value
    )

    Write-Host "Setting $path\$name to $value..."

    # Add or update the registry key
    C:\Windows\System32\reg.exe ADD "$path" /v "$name" /t $type /d $value /f

    Write-Host " "
}

# Related Group Policies: https://gpsearch.azurewebsites.net/#13739
# https://gpsearch.azurewebsites.net/#15676
# https://gpsearch.azurewebsites.net/#13435
# https://gpsearch.azurewebsites.net/#13436
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "AllowAutoWindowsUpdateDownloadOverMeteredNetwork" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "DeferFeatureUpdates" "REG_DWORD" "1"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "DeferFeatureUpdatesPeriodInDays" "REG_DWORD" "0x16d" # 365 in base 16
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "DeferQualityUpdates" "REG_DWORD" "1"
# Delay quality updates for 3 weeks and then push them to Saturdays
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "DeferQualityUpdatesPeriodInDays" "REG_DWORD" "0x19" # 25 in base 16
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "DeferUpgrade" "REG_DWORD" "1"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "DeferUpgradePeriod" "REG_DWORD" "1"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "DisableWUfBSafeguards" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "ManagePreviewBuilds" "REG_DWORD" "1"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "ManagePreviewBuildsPolicyValue" "REG_DWORD" "0"

Write-Host "--------------------------------------"

# Related Group Policies: https://gpsearch.azurewebsites.net/#2791
# https://gpsearch.azurewebsites.net/#2799
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "AllowMUUpdateService" "REG_DWORD" "1"
# Use this setting if you want to fully control when windows updates happen
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "AUOptions" "REG_DWORD" "2"
# Use the 3 settings below if you're setting up a computer for non-tech people lol
# windows will only update itself on the last Saturday of each month
##Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "AUOptions" "REG_DWORD" "4"
##Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "ScheduledInstallDay" "REG_DWORD" "7"
##Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "ScheduledInstallFourthWeek" "REG_DWORD" "1"
##Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "ScheduledInstallTime" "REG_DWORD" "0x18" # 24 in base 16
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "AUPowerManagement" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "NoAutoRebootWithLoggedOnUsers" "REG_DWORD" "1"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "NoAutoUpdate" "REG_DWORD" "1"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "AllowAutoWindowsUpdateDownloadOverMeteredNetwork" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "DeferFeatureUpdatesPeriodInDays" "REG_DWORD" "0x16d" # 365 in base 16
# Delay quality updates for 3 weeks and then push them to Saturdays
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "DeferQualityUpdatesPeriodInDays" "REG_DWORD" "0x19" # 25 in base 16
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "InsiderProgramEnabled" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "IsContinuousInnovationOptedIn" "REG_DWORD" "0"

Write-Host "--------------------------------------"

Write-Host "=======================" -ForegroundColor Green
Write-Host "== Process complete. ==" -ForegroundColor Green
Write-Host "=======================" -ForegroundColor Green
