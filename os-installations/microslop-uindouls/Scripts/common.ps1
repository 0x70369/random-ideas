# Shared helper, dot-sourced by the reg_*.ps1 scripts.
# Numbers are written as REG_DWORD, text as REG_SZ.
function Set-RegValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] $Value
    )
    if (-not $PSCmdlet.ShouldProcess("${Path}\${Name}", "Set ${Value}")) {
        return
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -Path $Path -Force
    }
    $type = 'DWord'
    if ($Value -is [string]) {
        $type = 'String'
    }
    $property = @{
        LiteralPath  = $Path
        Name         = $Name
        Value        = $Value
        PropertyType = $type
        Force        = $true
    }
    $null = New-ItemProperty @property
    Write-Output "${Path}\${Name} = ${Value}"
}
