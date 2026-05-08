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
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "DisableEdgeDesktopShortcutCreation" "REG_DWORD" "1"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge" "AutofillCreditCardEnabled" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge" "StartupBoostEnabled" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge" "UserFeedbackAllowed" "REG_DWORD" "0"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" "DoNotUpdateToEdgeWithChromium" "REG_DWORD" "1"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" "InstallDefault" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" "CreateDesktopShortcutDefault" "REG_DWORD" "0"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" "Install{0D50BFEC-CD6A-4F9A-964C-C7416E3ACB10}" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" "CreateDesktopShortcut{0D50BFEC-CD6A-4F9A-964C-C7416E3ACB10}" "REG_DWORD" "0"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" "Install{2CD8A007-E189-409D-A2C8-9AF4EF3C72AA}" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" "CreateDesktopShortcut{2CD8A007-E189-409D-A2C8-9AF4EF3C72AA}" "REG_DWORD" "0"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" "Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" "CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" "REG_DWORD" "0"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" "Install{65C35B14-6C1D-4122-AC46-7148CC9D6497}" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" "CreateDesktopShortcut{65C35B14-6C1D-4122-AC46-7148CC9D6497}" "REG_DWORD" "0"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" "Install{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" "CreateDesktopShortcut{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" "REG_DWORD" "0"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdateDev" "AllowUninstall" "REG_DWORD" "1"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdateDev" "CanContinueWithMissingUpdate" "REG_DWORD" "1"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\MicrosoftEdge" "PreventAccessToMicrosoftEdge" "REG_DWORD" "1"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\MicrosoftEdge" "PreventLaunchEdge" "REG_DWORD" "1"

Write-Host "--------------------------------------"

<#
These keys aren't working, I don't know why...
For now, you'll have to add/change them manually
Write-Host "Modifying MicrosoftEdge\Main key..."
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" "AllowPrelaunch" "REG_DWORD" "0"
Write-Host "--------------------------------------"

Write-Host "Modifying MicrosoftEdge\TabPreloader key..."
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\MicrosoftEdge\TabPreloader" "AllowTabPreloading" "REG_DWORD" "0"
Write-Host "--------------------------------------"
#>

Write-Host "=======================" -ForegroundColor Green
Write-Host "== Process complete. ==" -ForegroundColor Green
Write-Host "=======================" -ForegroundColor Green
