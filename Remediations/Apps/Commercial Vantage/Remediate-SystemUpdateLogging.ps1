Write-Output -InputObject "Enabling System Update Logging..."
$Path = "HKLM:\SOFTWARE\WOW6432Node\Lenovo\SystemUpdateAddin\Logs"
If (-not(Test-Path -Path $Path)) {
    New-Item -Path $Path -Force
}
Set-ItemProperty $Path EnableLogs -Value $true