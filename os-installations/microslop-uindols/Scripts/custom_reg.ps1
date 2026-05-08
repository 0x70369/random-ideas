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
Set-RegistryKey "HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" "System.IsPinnedToNameSpaceTree" "REG_DWORD" "1"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" "HarvestContacts" "REG_DWORD" "0"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Siuf\Rules" "PeriodInNanoSeconds" "REG_DWORD" "0"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "ContentDeliveryAllowed" "REG_DWORD" "0"
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "OemPreInstalledAppsEnabled" "REG_DWORD" "0"
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "PreInstalledAppsEnabled" "REG_DWORD" "0"
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SilentInstalledAppsEnabled" "REG_DWORD" "0"
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SoftLandingEnabled" "REG_DWORD" "0"
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-310093Enabled" "REG_DWORD" "0"
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338388Enabled" "REG_DWORD" "0"
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SystemPaneSuggestionsEnabled" "REG_DWORD" "0"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Hidden" "REG_DWORD" "1"
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideDrivesWithNoMedia" "REG_DWORD" "0"
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" "REG_DWORD" "0"
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowCopilotButton" "REG_DWORD" "0"
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowCortanaButton" "REG_DWORD" "0"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel" "AllItemsIconView" "REG_DWORD" "0"
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel" "StartupPage" "REG_DWORD" "1"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" "EnthusiastMode" "REG_DWORD" "1"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds\DSB" "ShowDynamicContent" "REG_DWORD" "0"

Write-Host "--------------------------------------"

# https://www.reddit.com/r/sysadmin/comments/16iwimf/comment/k1btfaz/
# Set this key with caution
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Microsoft.SkyDrive.Desktop" "Enabled" "REG_DWORD" "0"

# https://www.reddit.com/r/Intune/comments/16i8arf/comment/k1axq75/
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.BackupReminder" "Enabled" "REG_DWORD" "0"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" "REG_DWORD" "0"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" "IsDynamicSearchBoxEnabled" "REG_DWORD" "0"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" "REG_DWORD" "0"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\InputPersonalization" "AllowInputPersonalization" "REG_DWORD" "1"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\InputPersonalization" "RestrictImplicitTextCollection" "REG_DWORD" "1"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\InputPersonalization" "RestrictImplicitInkCollection" "REG_DWORD" "1"

Write-Host "--------------------------------------"

# https://www.reddit.com/r/Intune/comments/16i8arf/comment/m26foqf/
# Only uncomment the line below if you know for sure that you won't use a M$ account >>anywhere<< on the system
##Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\MicrosoftAccount" "DisableUserAuth" "REG_DWORD" "1"

#Write-Host "--------------------------------------"

# https://www.reddit.com/r/sysadmin/comments/16iwimf/comment/k3kruke/
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\OneDrive" "KFMBlockOptIn" "REG_DWORD" "1"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" "DisabledByGroupPolicy" "REG_DWORD" "1"

Write-Host "--------------------------------------"

# Related Group Policies: https://gpsearch.azurewebsites.net/#10937
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowDeviceNameInTelemetry" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "DisableOneSettingsDownloads" "REG_DWORD" "1"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "DoNotShowFeedbackNotifications" "REG_DWORD" "1"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "LimitDiagnosticLogCollection" "REG_DWORD" "1"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" "PreventDeviceMetadataFromNetwork" "REG_DWORD" "1"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" "REG_DWORD" "1"
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Policies\Microsoft\Windows\Explorer" "EnableLegacyBalloonNotifications" "REG_DWORD" "0" # On W10 setting this to 1 works, not on W11
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Policies\Microsoft\Windows\Explorer" "HidePeopleBar" "REG_DWORD" "1"
Set-RegistryKey "HKEY_CURRENT_USER\SOFTWARE\Policies\Microsoft\Windows\Explorer" "NoBalloonFeatureAdvertisements" "REG_DWORD" "1"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" "REG_DWORD" "1"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCloudSearch" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortanaAboveLock" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowSearchToUseLocation" "REG_DWORD" "0"
Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "DisableWebSearch" "REG_DWORD" "1"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" "REG_DWORD" "0"

Write-Host "--------------------------------------"

Set-RegistryKey "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" "RealTimeIsUniversal" "REG_DWORD" "1"

Write-Host "--------------------------------------"

Write-Host "=======================" -ForegroundColor Green
Write-Host "== Process complete. ==" -ForegroundColor Green
Write-Host "=======================" -ForegroundColor Green
