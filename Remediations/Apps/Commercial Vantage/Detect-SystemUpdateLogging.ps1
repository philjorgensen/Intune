$Path = "HKLM:\SOFTWARE\WOW6432Node\Lenovo\SystemUpdateAddin\Logs"
$Name = "EnableLogs"
$Value = $true

try {
    $Registry = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop | Select-Object -ExpandProperty $Name
    If ($Registry -eq $Value){
        Write-Output -InputObject "System Update logging enabled."
        Exit 0
    } 
    Write-Warning -Message "System Update logging not enabled."
    Exit 1
} 
catch {
    Write-Warning -Message "Could not enable System Update logging..."
    Exit 1
}