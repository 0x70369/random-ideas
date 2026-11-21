#Requires -RunAsAdministrator
# Keep the hardware clock in UTC, as Linux does, for dual boot.
. "${PSScriptRoot}\common.ps1"

$tz = 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation'
Set-RegValue $tz RealTimeIsUniversal 1
