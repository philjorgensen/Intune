# Change this variable to the version you're deploying
$DeployedVantageVersion = "10.2407.66.0"

$ErrorActionPreference = "Stop"

try {

    If (Get-Service -Name ImControllerService) {
    
    }
        
    If (Get-Service -Name LenovoVantageService) {
        # Check for older of version of Vantage Service that causes UAC prompt. This is due to an expired certificate.  
        $minVersion = "3.8.23.0"
        $path = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath "Lenovo\VantageService\*\LenovoVantageService.exe" -Resolve
        $path = ${env:ProgramFiles(x86)} + "\Lenovo\VantageService\*\LenovoVantageService.exe"
        $version = (Get-ChildItem -Path $path).VersionInfo.FileVersion
        if ($version.Count -gt 1) {
            $version = $version[-1]
        }
            
        if ([version]$version -le [version]$minVersion) {
            
            Write-Output "Vantage Service outdated."; exit 1
        }
    }
        
    # Assume no version is installed
    $InstalledVersion = $false
    
    # For specific Appx version
    $InstalledVantageVersion = (Get-AppxPackage -Name E046963F.LenovoSettingsforEnterprise -AllUsers).Version

    If ([version]$InstalledVantageVersion -ge [version]$DeployedVantageVersion) {
        $InstalledVersion = $true
        
        # For package name only    
        # If (Get-AppxPackage -Name E046963F.LenovoSettingsforEnterprise -AllUsers) {

    }

    if ($InstalledVersion) {
        Write-Output "All Vantage Services and Appx Present"; exit 0
    }
    else {
        Write-Output "Commercial Vantage is outdated."; exit 1
    }
}
catch {
    
    Write-Output $_.Exception.Message; exit 1
}
