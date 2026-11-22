#Requires -RunAsAdministrator
# Keep Microsoft Edge from installing, updating and running by itself.
# WebView2 ({F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}) stays allowed: apps
# depend on it.
. "${PSScriptRoot}\common.ps1"

$cv = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion'
Set-RegValue "${cv}\Explorer" DisableEdgeDesktopShortcutCreation 1

# https://gpsearch.azurewebsites.net/?PolicyID=14713
# https://gpsearch.azurewebsites.net/?PolicyID=15406
# https://gpsearch.azurewebsites.net/?PolicyID=14944
$edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
Set-RegValue $edge AutofillCreditCardEnabled 0
Set-RegValue $edge StartupBoostEnabled 0
Set-RegValue $edge UserFeedbackAllowed 0

$eu = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
Set-RegValue $eu DoNotUpdateToEdgeWithChromium 1
# https://gpsearch.azurewebsites.net/?PolicyID=15094
# https://gpsearch.azurewebsites.net/?PolicyID=15338
Set-RegValue $eu InstallDefault 0
Set-RegValue $eu CreateDesktopShortcutDefault 0
# Install* policies only apply to devices joined to an AD domain.
# Edge Stable, Beta, Canary and Dev (the links are Stable's policies; each
# channel has its own)
$channels = @(
    '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
    '{2CD8A007-E189-409D-A2C8-9AF4EF3C72AA}'
    '{65C35B14-6C1D-4122-AC46-7148CC9D6497}'
    '{0D50BFEC-CD6A-4F9A-964C-C7416E3ACB10}'
)
# https://gpsearch.azurewebsites.net/?PolicyID=15097
# https://gpsearch.azurewebsites.net/?PolicyID=15339
foreach ($app in $channels) {
    Set-RegValue $eu "Install${app}" 0
    Set-RegValue $eu "CreateDesktopShortcut${app}" 0
}

$dev = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdateDev'
Set-RegValue $dev AllowUninstall 1
Set-RegValue $dev CanContinueWithMissingUpdate 1

# Legacy Edge (EdgeHTML), kept for completeness
$old = 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge'
Set-RegValue $old PreventAccessToMicrosoftEdge 1
Set-RegValue $old PreventLaunchEdge 1
# https://gpsearch.azurewebsites.net/?PolicyID=14095
# https://gpsearch.azurewebsites.net/?PolicyID=14093
Set-RegValue "${old}\Main" AllowPrelaunch 0
Set-RegValue "${old}\TabPreloader" AllowTabPreloading 0
