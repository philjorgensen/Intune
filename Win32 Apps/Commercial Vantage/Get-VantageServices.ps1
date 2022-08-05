$ErrorActionPreference = 'Stop'

try {

    If (Get-Service -Name ImControllerService) {
    
    }
        
    If (Get-Service -Name LenovoVantageService) {
        # Check for older of version of Vantage Service that causes UAC prompt. This is due to an expired certificate.  
        $minVersion = "3.8.23.0"
        $path = ${env:ProgramFiles(x86)} + "\Lenovo\VantageService\*\LenovoVantageService.exe"
        $version = (Get-ChildItem -Path $path).VersionInfo.FileVersion
            
        if ([version]$version -le [version]$minVersion) {
            
            Write-Output "Vantage Service outdated..."; Exit 1
        }
    }
        
    # For specific Appx version
    # If (Get-AppxPackage -AllUsers | Where-Object { $_.PackageFullName -match "LenovoSettingsforEnterprise_10.2102.10.0" }) {
        
    # For package name only    
    If (Get-AppxPackage -AllUsers | Where-Object { $_.Name -eq "E046963F.LenovoSettingsforEnterprise" }) {

    }

    Write-Output "All Vantage Services and Appx Present."; Exit 0

}
catch {
    
    Write-Output $_.Exception.Message; Exit 1
}
