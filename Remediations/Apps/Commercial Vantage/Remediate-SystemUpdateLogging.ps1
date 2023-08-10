Write-Output -InputObject "Enabling System Update Logging..."
$Path = "HKLM:\SOFTWARE\WOW6432Node\Lenovo\SystemUpdateAddin\Logs"
If (-not(Test-Path -Path $Path)) {
    New-Item -Path $Path
}
Set-ItemProperty $Path EnableLogs -Value $true