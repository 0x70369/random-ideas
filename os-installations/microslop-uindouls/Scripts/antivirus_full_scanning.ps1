# Check if the script is running with administrator privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "====================================================================" -ForegroundColor Red
    Write-Host "==   This script needs to be run with administrator privileges.   ==" -ForegroundColor Red
    Write-Host "==    Please open an elevated PowerShell prompt and try again.    ==" -ForegroundColor Red
    Write-Host "====================================================================" -ForegroundColor Red
    exit
}

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=================================================================================================" -ForegroundColor Yellow
Write-Host "==                               PLEASE, DO NOT CLOSE THIS WINDOW!                             ==" -ForegroundColor Red
Write-Host "==                  Windows Defender will perform a full system scan for viruses               ==" -ForegroundColor Yellow
Write-Host "== It is NORMAL for the system to be slower during the scanning, but you CAN continue using it ==" -ForegroundColor Yellow
Write-Host "==                This process might take many hours to complete, please be patient            ==" -ForegroundColor Yellow
Write-Host "==                 When the scanning is done, this window will close automatically             ==" -ForegroundColor Yellow
Write-Host "==                      DO NOT TURN OFF THE SYSTEM WHILE THIS WINDOW IS OPEN!                  ==" -ForegroundColor Red
Write-Host "=================================================================================================" -ForegroundColor Yellow

Write-Host ""

Start-Sleep -Seconds 5

cd "C:\Program Files\Windows Defender"

Write-Host "Updating virus definitions..." -ForegroundColor Yellow
.\MpCmdRun.exe -SignatureUpdate

Write-Host ""

Write-Host "Scanning boot files..." -ForegroundColor Yellow
.\MpCmdRun.exe -Scan -ScanType -BootSectorScan

Write-Host ""

Write-Host "Scanning the system..." -ForegroundColor Yellow
.\MpCmdRun.exe -Scan -ScanType 2

Write-Host ""

Write-Host "==================================================================================" -ForegroundColor Green
Write-Host "== Scanning complete. You can open 'Windows Security' to see the scan's results ==" -ForegroundColor Green
Write-Host "==              This window will close automatically in 10 seconds              ==" -ForegroundColor Green
Write-Host "==================================================================================" -ForegroundColor Green

Start-Sleep -Seconds 10

exit
