#Requires -RunAsAdministrator
# Explorer, Start menu, taskbar and notifications of the current user.
. "${PSScriptRoot}\common.ps1"

# Suggestions, ads and silently installed apps
$cdm = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$cdmValues = @(
    'ContentDeliveryAllowed'
    'OemPreInstalledAppsEnabled'
    'PreInstalledAppsEnabled'
    'SilentInstalledAppsEnabled'
    'SoftLandingEnabled'
    'SubscribedContent-310093Enabled'
    'SubscribedContent-338388Enabled'
    'SystemPaneSuggestionsEnabled'
)
foreach ($name in $cdmValues) {
    Set-RegValue $cdm $name 0
}

$cv = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion'
Set-RegValue "${cv}\Feeds\DSB" ShowDynamicContent 0
Set-RegValue "${cv}\SearchSettings" IsDynamicSearchBoxEnabled 0
Set-RegValue "${cv}\UserProfileEngagement" ScoobeSystemSettingEnabled 0
$toast = "${cv}\Notifications\Settings\Windows.SystemToast.BackupReminder"
Set-RegValue $toast Enabled 0

$adv = "${cv}\Explorer\Advanced"
Set-RegValue $adv Hidden 1
Set-RegValue $adv HideDrivesWithNoMedia 0
Set-RegValue $adv HideFileExt 0
Set-RegValue $adv ShowCopilotButton 0
Set-RegValue $adv ShowCortanaButton 0
Set-RegValue $adv ShowSecondsInSystemClock 1
Set-RegValue "${cv}\Explorer\ControlPanel" AllItemsIconView 0
Set-RegValue "${cv}\Explorer\ControlPanel" StartupPage 1
Set-RegValue "${cv}\Explorer\OperationStatusManager" EnthusiastMode 1

$ex = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
# 1 restores the old balloons on Windows 10, but not on Windows 11
Set-RegValue $ex EnableLegacyBalloonNotifications 0
Set-RegValue $ex HidePeopleBar 1
Set-RegValue $ex NoBalloonFeatureAdvertisements 1
