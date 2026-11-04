$folder = 'C:\tmp'

# Do nothing if the folder doesn't exist, so a wrong path never deletes anything else
if (Test-Path -LiteralPath $folder -PathType Container) {
    Get-ChildItem -LiteralPath $folder -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}