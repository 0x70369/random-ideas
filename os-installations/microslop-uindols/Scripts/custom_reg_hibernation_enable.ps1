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

# Define the registry keys and values
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" "ShowHibernateOption" "REG_DWORD" "1"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" "ShowLockOption" "REG_DWORD" "1"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" "ShowSleepOption" "REG_DWORD" "1"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HibernateEnabled" "REG_DWORD" "1"

Write-Host "--------------------------------------"

Write-Host "Enabling hibernation... "
Start-Process -FilePath "C:\Windows\System32\powercfg.exe" -ArgumentList "/hibernate on" -NoNewWindow -Wait

Write-Host "--------------------------------------"

Write-Host "=======================" -ForegroundColor Green
Write-Host "== Process complete. ==" -ForegroundColor Green
Write-Host "=======================" -ForegroundColor Green
