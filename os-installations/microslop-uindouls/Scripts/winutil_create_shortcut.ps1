<#
.SYNOPSIS
    Creates a WinUtil shortcut (.lnk) identical to the one produced by the
    "Create WinUtil Shortcut" button, but resolving pwsh.exe through the PATH
    at click time - instead of baking in a versioned absolute path that breaks
    on every PowerShell update.

.DESCRIPTION
    The shortcut targets %SystemRoot%\System32\cmd.exe (a fixed system path).
    cmd, in turn, calls "pwsh.exe" by NAME only and resolves the executable
    through the PATH at the moment the shortcut is clicked. That way the .lnk
    is never tied to a specific PowerShell folder.

    The WinUtil command is passed via -EncodedCommand (Base64), which prevents
    cmd from interpreting the quotes and the pipe ( | ) in the original
    command. What ultimately runs is identical to the WinUtil shortcut.

.PARAMETER Path
    Path/name of the .lnk to create. If omitted, a "Save as" dialog opens on
    the Desktop, just like WinUtil does.

.PARAMETER RunAsAdmin
    Turns on the "Run as administrator" flag on the shortcut.
    Default: $true (same behavior as the WinUtil button).

.EXAMPLE
    .\winutil_create_shortcut.ps1

.EXAMPLE
    .\winutil_create_shortcut.ps1 -Path "$env:USERPROFILE\Desktop\WinUtil.lnk"
#>

param (
    [string]$Path,
    [bool]$RunAsAdmin = $true
)

Add-Type -AssemblyName System.Windows.Forms

# --- 1. Pick the launcher (PS7 if available, otherwise Windows PowerShell) ----
# Only the executable NAME is used; the PATH resolves it at launch time.
if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    $launcher = "pwsh.exe"
} else {
    $launcher = "powershell.exe"
}

# --- 2. Build the WinUtil command (identical to the original) -----------------
# Re-launches elevated and runs winutil.ps1 straight from the latest release.
$innerCommand = "Start-Process $launcher -Verb RunAs -ArgumentList '-Command `"irm https://github.com/ChrisTitusTech/winutil/releases/latest/download/winutil.ps1 | iex`"'"
$encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($innerCommand))

# --- 3. Figure out where to save the .lnk ------------------------------------
if (-not $Path) {
    $FileBrowser = New-Object System.Windows.Forms.SaveFileDialog
    $FileBrowser.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    $FileBrowser.Filter = "Shortcut Files (*.lnk)|*.lnk"
    $FileBrowser.FileName = "WinUtil.lnk"
    if ($FileBrowser.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "Operation cancelled."
        return
    }
    $Path = $FileBrowser.FileName
}

# --- 4. Download the WinUtil icon (local cache) if it isn't there yet ---------
$iconDir  = Join-Path $env:LOCALAPPDATA "winutil"
$iconPath = Join-Path $iconDir "cttlogo.ico"
if (-not (Test-Path $iconPath)) {
    try {
        [System.IO.Directory]::CreateDirectory($iconDir) | Out-Null
        Invoke-WebRequest -Uri "https://christitus.com/images/logo-full.ico" -OutFile $iconPath -ErrorAction Stop
    } catch {
        Write-Warning "Could not download the icon; the shortcut will keep cmd's default icon."
    }
}

# --- 5. Create the shortcut: cmd (fixed) -> pwsh.exe (resolved via PATH) ------
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($Path)
$Shortcut.TargetPath  = "$env:SystemRoot\System32\cmd.exe"
$Shortcut.Arguments   = "/c start `"`" $launcher -ExecutionPolicy Bypass -EncodedCommand $encoded"
$Shortcut.WindowStyle = 1
if (Test-Path $iconPath) {
    $Shortcut.IconLocation = $iconPath
}
$Shortcut.Save()

# --- 6. Turn on the "Run as administrator" flag on the .lnk, if requested -----
if ($RunAsAdmin) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    # Set bit 0x20 in byte 0x15 (the "Run as administrator" flag of the .lnk format)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($Path, $bytes)
}

Write-Host "Shortcut created at: $Path"
Write-Host "TargetPath : $($Shortcut.TargetPath)"
Write-Host "Launcher   : $launcher (resolved via PATH at click time)"
