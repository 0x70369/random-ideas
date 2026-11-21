#Requires -RunAsAdministrator
# Turn off Internet Explorer: block the standalone app and Edge's IE mode,
# then remove the Windows component. The MSHTML engine stays (Windows and
# other apps use it).
. "${PSScriptRoot}\common.ps1"

foreach ($hive in 'HKLM:', 'HKCU:') {
    $pol = "${hive}\SOFTWARE\Policies\Microsoft"
    # 0 = IE disabled, users are never notified
    Set-RegValue "${pol}\Internet Explorer\Main" NotifyDisableIEOptions 0
    # 0 = no IE integration in Edge
    Set-RegValue "${pol}\Edge" InternetExplorerIntegrationLevel 0
}

# Same command as Microsoft's KB4013567. /NoRestart skips the Y/N prompt.
$capability = '/CapabilityName:Browser.InternetExplorer~~~~0.0.11.0'
& "${env:SystemRoot}\System32\dism.exe" /Online /Remove-Capability `
    $capability
