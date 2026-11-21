#Requires -RunAsAdministrator
# Turn hibernation off and hide it from the power menu. Fast startup stays off.
. "${PSScriptRoot}\common.ps1"

$cv = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion'
$fm = "${cv}\Explorer\FlyoutMenuSettings"
Set-RegValue $fm ShowHibernateOption 0
Set-RegValue $fm ShowLockOption 1
Set-RegValue $fm ShowSleepOption 1

$pw = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
Set-RegValue $pw HiberbootEnabled 0
Set-RegValue $pw HibernateEnabled 0

& "${env:SystemRoot}\System32\powercfg.exe" /hibernate off
