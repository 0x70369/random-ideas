#Requires -RunAsAdministrator
# Update Microsoft Defender, then scan the boot sectors and the whole system.
# The full scan can take hours; the computer stays usable meanwhile.
$mpCmdRun = "${env:ProgramFiles}\Windows Defender\MpCmdRun.exe"

Write-Output 'Updating security intelligence...'
& $mpCmdRun -SignatureUpdate

# -BootSectorScan only works with a custom scan (type 3), which needs a path:
# the boot files folder keeps that extra scan short.
Write-Output 'Scanning the boot sectors...'
& $mpCmdRun -Scan -ScanType 3 -File "${env:SystemRoot}\Boot" -BootSectorScan

Write-Output 'Scanning the whole system. Do not turn the computer off.'
& $mpCmdRun -Scan -ScanType 2

Write-Output 'Done. The results are in Windows Security > Protection history.'
$null = Read-Host 'Press Enter to close'
