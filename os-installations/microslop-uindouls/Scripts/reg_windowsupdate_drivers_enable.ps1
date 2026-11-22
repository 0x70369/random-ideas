#Requires -RunAsAdministrator
# Let Windows Update install and offer drivers.
. "${PSScriptRoot}\common.ps1"

# https://gpsearch.azurewebsites.net/?PolicyID=13437
$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
Set-RegValue $wu ExcludeWUDriversInQualityUpdate 0
$ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
Set-RegValue $ux ExcludeWUDriversInQualityUpdate 0

# https://gpsearch.azurewebsites.net/?PolicyID=181
# https://gpsearch.azurewebsites.net/?PolicyID=4721
# https://gpsearch.azurewebsites.net/?PolicyID=183
$ds = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching'
Set-RegValue $ds DontPromptForWindowsUpdate 0
Set-RegValue $ds DontSearchWindowsUpdate 0
Set-RegValue $ds DriverUpdateWizardWuSearchEnabled 1
# 0 = never search Windows Update, 1 = always
Set-RegValue $ds SearchOrderConfig 1
