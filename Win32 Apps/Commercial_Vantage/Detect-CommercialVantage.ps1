# Version of Lenovo Vantage that is being deployed
$DeployedVantageVersion = [version]"20.2506.39.0"

try
{
    # Get the path to the most recent VantageService folder under ProgramFiles(x86)
    $vantageServicePath = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Lenovo\VantageService" -Directory | Select-Object -Last 1

    # Check if the path exists before proceeding
    if ($vantageServicePath)
    {
        # Find LenovoVantageService.exe in the directory
        $vantageServiceFile = Get-ChildItem -Path $vantageServicePath.FullName -Filter "LenovoVantageService.exe" -File -Recurse -ErrorAction Stop | Select-Object -Last 1

        if ($vantageServiceFile)
        {
            # Extract the version information
            $serviceVersion = [version]$vantageServiceFile.VersionInfo.FileVersion
        }
        else
        {
            $serviceVersion = $null
            Write-Warning "LenovoVantageService.exe was not found."
        }
    }
    else
    {
        $serviceVersion = $null
        Write-Warning "VantageService directory was not found."
    }


    $minServiceVersion = [version]"3.8.23.0"
    if ($serviceVersion -le $minServiceVersion)
    {
        Write-Output "Lenovo Vantage Service is outdated (found version $serviceVersion, required minimum $minServiceVersion)."
        exit 1
    }
}
catch
{
    Write-Output "Failed to retrieve Lenovo Vantage Service version. Error: $($_.Exception.Message)"
    exit 1
}

# Check for the Lenovo Commercial Vantage APPX package
try
{
    $vantagePackage = Get-AppxPackage -Name E046963F.LenovoSettingsforEnterprise -AllUsers -ErrorAction Stop
    $installedVersion = [version]$vantagePackage.Version

    if ($installedVersion -ge $DeployedVantageVersion)
    {
        Write-Output "Lenovo Commercial Vantage APPX package is up-to-date (installed version: $installedVersion, required version: $DeployedVantageVersion)."
        exit 0
    }
    else
    {
        Write-Output "Lenovo Commercial Vantage APPX package is outdated (installed version: $installedVersion, required version: $DeployedVantageVersion)."
        exit 1
    }
}
catch
{
    Write-Output "Failed to detect Lenovo Commercial Vantage APPX package. Error: $($_.Exception.Message)"
    exit 1
}