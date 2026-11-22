#Requires -RunAsAdministrator
# Stop Windows Update from installing or offering drivers.
. "${PSScriptRoot}\common.ps1"

# https://gpsearch.azurewebsites.net/?PolicyID=13437
$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
Set-RegValue $wu ExcludeWUDriversInQualityUpdate 1
$ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
Set-RegValue $ux ExcludeWUDriversInQualityUpdate 1

# https://gpsearch.azurewebsites.net/?PolicyID=181
# https://gpsearch.azurewebsites.net/?PolicyID=4721
# https://gpsearch.azurewebsites.net/?PolicyID=183
$ds = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching'
Set-RegValue $ds DontPromptForWindowsUpdate 1
Set-RegValue $ds DontSearchWindowsUpdate 1
Set-RegValue $ds DriverUpdateWizardWuSearchEnabled 0
# 0 = never search Windows Update, 1 = always
Set-RegValue $ds SearchOrderConfig 0
