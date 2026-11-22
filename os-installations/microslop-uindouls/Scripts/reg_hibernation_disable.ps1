#Requires -RunAsAdministrator
# Turn hibernation off and hide it from the power menu. Fast startup stays off.
. "${PSScriptRoot}\common.ps1"

# https://gpsearch.azurewebsites.net/?PolicyID=10651
# https://gpsearch.azurewebsites.net/?PolicyID=10649
# https://gpsearch.azurewebsites.net/?PolicyID=10650
$ex = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
Set-RegValue $ex ShowHibernateOption 0
Set-RegValue $ex ShowLockOption 1
Set-RegValue $ex ShowSleepOption 1

$pw = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
# Fast startup off. No policy can force it off ("Require use of fast startup"
# only forces it on), so this is the local setting.
Set-RegValue $pw HiberbootEnabled 0
Set-RegValue $pw HibernateEnabled 0

& "${env:SystemRoot}\System32\powercfg.exe" /hibernate off
