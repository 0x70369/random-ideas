#Requires -RunAsAdministrator
# Delay updates, block preview builds, install on the 4th Saturday.
. "${PSScriptRoot}\common.ps1"

# https://gpsearch.azurewebsites.net/?PolicyID=13739
# https://gpsearch.azurewebsites.net/?PolicyID=15676
# https://gpsearch.azurewebsites.net/?PolicyID=13435
# https://gpsearch.azurewebsites.net/?PolicyID=13436
$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
Set-RegValue $wu AllowAutoWindowsUpdateDownloadOverMeteredNetwork 0
Set-RegValue $wu DeferFeatureUpdates 1
Set-RegValue $wu DeferFeatureUpdatesPeriodInDays 365
Set-RegValue $wu DeferQualityUpdates 1
# Patch Tuesday + 25 days = 3 weeks and 4 days later, a Saturday
Set-RegValue $wu DeferQualityUpdatesPeriodInDays 25
Set-RegValue $wu DeferUpgrade 1
Set-RegValue $wu DeferUpgradePeriod 1
Set-RegValue $wu DisableWUfBSafeguards 0
Set-RegValue $wu ManagePreviewBuilds 1
# 1 = policy disabled: no pre-release builds
Set-RegValue $wu ManagePreviewBuildsPolicyValue 1

# https://gpsearch.azurewebsites.net/?PolicyID=2791
# https://gpsearch.azurewebsites.net/?PolicyID=2799
$au = "${wu}\AU"
Set-RegValue $au NoAutoUpdate 0
Set-RegValue $au AllowMUUpdateService 1
# 4 = download and install on a schedule; 2 = only notify, you install
Set-RegValue $au AUOptions 4
# Fourth Saturday of the month, at 08:00 (24 = "Automatic" would ignore
# the day and the week)
Set-RegValue $au ScheduledInstallDay 7
Set-RegValue $au ScheduledInstallFourthWeek 1
Set-RegValue $au ScheduledInstallTime 8
Set-RegValue $au AUPowerManagement 0
Set-RegValue $au NoAutoRebootWithLoggedOnUsers 1

# Same choices in the Settings app
$ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
Set-RegValue $ux AllowAutoWindowsUpdateDownloadOverMeteredNetwork 0
Set-RegValue $ux DeferFeatureUpdatesPeriodInDays 365
Set-RegValue $ux DeferQualityUpdatesPeriodInDays 25
Set-RegValue $ux InsiderProgramEnabled 0
Set-RegValue $ux IsContinuousInnovationOptedIn 0
