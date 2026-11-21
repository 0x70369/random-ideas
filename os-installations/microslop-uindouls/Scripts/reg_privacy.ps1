#Requires -RunAsAdministrator
# Stop every data upload to Microsoft that a policy can turn off, except
# Defender cloud protection and SmartScreen, which stay on.
. "${PSScriptRoot}\common.ps1"

$pol = 'HKLM:\SOFTWARE\Policies\Microsoft'
$win = "${pol}\Windows"

# Diagnostic data: 0 turns it off on Enterprise, Education and Server; the
# other editions treat 0 as 1 (required), the lowest level they accept.
# Each key is read separately: group policy (machine and user), local
# preference and its 32-bit view.
# https://gpsearch.azurewebsites.net/?PolicyID=13549
$dc = "${win}\DataCollection"
$cv = 'Microsoft\Windows\CurrentVersion\Policies\DataCollection'
$telemetryKeys = @(
    $dc
    'HKCU:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    "HKLM:\SOFTWARE\${cv}"
    "HKLM:\SOFTWARE\WOW6432Node\${cv}"
)
foreach ($key in $telemetryKeys) {
    Set-RegValue $key AllowTelemetry 0
}
Set-RegValue $dc AllowDeviceNameInTelemetry 0
Set-RegValue $dc DisableEnterpriseAuthProxy 1
Set-RegValue $dc DisableOneSettingsDownloads 1
Set-RegValue $dc DisableTelemetryOptInChangeNotification 1
Set-RegValue $dc DisableTelemetryOptInSettingsUx 1
Set-RegValue $dc DoNotShowFeedbackNotifications 1
Set-RegValue $dc LimitDiagnosticLogCollection 1
Set-RegValue $dc LimitDumpCollection 1

# Error reports ("Turn off Windows Error Reporting" writes both values),
# CEIP, application telemetry and inventory
Set-RegValue "${win}\Windows Error Reporting" Disabled 1
Set-RegValue "${pol}\PCHealth\ErrorReporting" DoReport 0
Set-RegValue "${pol}\SQMClient\Windows" CEIPEnable 0
Set-RegValue "${win}\AppCompat" AITEnable 0
Set-RegValue "${win}\AppCompat" DisableInventory 1
Set-RegValue 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' PeriodInNanoSeconds 0
Set-RegValue "${win}\PreviewBuilds" EnableExperimentation 0

# Ads and Microsoft "experiences" (the last one: Enterprise and Education)
$cc = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
Set-RegValue $cc DisableTailoredExperiencesWithDiagnosticData 1
Set-RegValue "${win}\AdvertisingInfo" DisabledByGroupPolicy 1
Set-RegValue "${win}\CloudContent" DisableWindowsConsumerFeatures 1
Set-RegValue "${win}\Device Metadata" PreventDeviceMetadataFromNetwork 1

# Inking and typing data (machine and user policies)
foreach ($hive in 'HKLM', 'HKCU') {
    $ip = "${hive}:\SOFTWARE\Policies\Microsoft\InputPersonalization"
    Set-RegValue $ip RestrictImplicitInkCollection 1
    Set-RegValue $ip RestrictImplicitTextCollection 1
}
$td = 'HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore'
Set-RegValue $td HarvestContacts 0
$ti = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\TextInput'
Set-RegValue $ti AllowLinguisticDataCollection 0
Set-RegValue "${win}\TabletPC" PreventHandwritingDataSharing 1
$hw = "${win}\HandwritingErrorReports"
Set-RegValue $hw PreventHandwritingErrorReports 1

# Search: no web, Cortana, highlights or history; Bing gets anonymous info
$ws = "${win}\Windows Search"
Set-RegValue $ws AllowCloudSearch 0
Set-RegValue $ws AllowCortana 0
Set-RegValue $ws AllowCortanaAboveLock 0
Set-RegValue $ws AllowSearchToUseLocation 0
Set-RegValue $ws ConnectedSearchPrivacy 3
Set-RegValue $ws ConnectedSearchUseWeb 0
Set-RegValue $ws DisableWebSearch 1
Set-RegValue $ws EnableDynamicContentInWSB 0
$ex = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
Set-RegValue $ex DisableSearchBoxSuggestions 1
Set-RegValue $ex DisableSearchHistory 1

# Copilot (the official policy is the user one; the machine one is kept
# anyway) and Recall: snapshots off, component removed (24H2 or later)
foreach ($hive in 'HKCU', 'HKLM') {
    $ai = "${hive}:\SOFTWARE\Policies\Microsoft\Windows"
    Set-RegValue "${ai}\WindowsCopilot" TurnOffWindowsCopilot 1
    Set-RegValue "${ai}\WindowsAI" DisableAIDataAnalysis 1
}
Set-RegValue "${win}\WindowsAI" AllowRecallEnablement 0

# Cloud sync: clipboard, activity history, settings, text messages
$sys = "${win}\System"
Set-RegValue $sys AllowCrossDeviceClipboard 0
Set-RegValue $sys EnableActivityFeed 0
Set-RegValue $sys PublishUserActivities 0
Set-RegValue $sys UploadUserActivities 0
Set-RegValue "${win}\SettingSync" DisableSettingSync 2
Set-RegValue "${win}\SettingSync" DisableSettingSyncUserOverride 1
Set-RegValue "${win}\Messaging" AllowMessageSync 0

# Updates only from Microsoft over HTTP: no peers, no DO cloud service
Set-RegValue "${win}\DeliveryOptimization" DODownloadMode 99
Set-RegValue "${pol}\FindMyDevice" AllowFindMyDevice 0
# Widgets (Windows 11) and news and interests (Windows 10)
Set-RegValue "${pol}\Dsh" AllowNewsAndInterests 0
Set-RegValue "${win}\Windows Feeds" EnableFeeds 0

# Old Internet Communication Management settings that still contact
# Microsoft: file association lookup, web wizards, Event Viewer links and
# KMS online validation
$exp = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
Set-RegValue $exp NoInternetOpenWith 1
Set-RegValue $exp NoOnlinePrintsWizard 1
Set-RegValue $exp NoPublishingWizard 1
Set-RegValue $exp NoWebServices 1
Set-RegValue "${pol}\EventViewer" MicrosoftEventVwrDisableLinks 1
$spp = "${pol}\Windows NT\CurrentVersion\Software Protection Platform"
Set-RegValue $spp NoGenTicket 1

# Edge, if it is still installed: no diagnostic data or browsing data
foreach ($hive in 'HKLM', 'HKCU') {
    $edge = "${hive}:\SOFTWARE\Policies\Microsoft\Edge"
    Set-RegValue $edge DiagnosticData 0
    Set-RegValue $edge PersonalizationReportingEnabled 0
}

# Defender cloud protection at Microsoft's security baseline (advanced MAPS,
# all samples sent). SmartScreen warns about unknown apps; the user may run
# them anyway.
# Tamper Protection ignores the Defender values while it is on.
$spy = "${pol}\Windows Defender\Spynet"
Set-RegValue $spy SpynetReporting 2
Set-RegValue $spy SubmitSamplesConsent 3
Set-RegValue $sys EnableSmartScreen 1
Set-RegValue $sys ShellSmartScreenLevel 'Warn'

# Hides the "Windows Backup" app, but blocks Microsoft accounts in every app
# and service (Store included). Signing in to Windows and websites with one
# still works.
# Set-RegValue "${pol}\MicrosoftAccount" DisableUserAuth 1
