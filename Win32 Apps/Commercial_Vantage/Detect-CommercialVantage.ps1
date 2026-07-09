# Version of Lenovo Vantage that is being deployed
$DeployedVantageVersion = [version]"20.2603.19.0"
# Minimum version requirements
$minServiceVersion = [version]"3.8.23.0"
# SUHelper check - set to $true to enable, $false to skip
$checkSUHelper = $true
$minSUHelperVersion = [version]"1.0.0.22"

try
{
    # Get the path to the most recent VantageService folder under ProgramFiles(x86)
    $vantageServicePath = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Lenovo\VantageService" -Directory -ErrorAction Stop | Select-Object -Last 1
    # Check if the path exists before proceeding
    if ($vantageServicePath)
    {
        # Find LenovoVantageService.exe in the directory
        $vantageServiceFile = Get-ChildItem -Path $vantageServicePath.FullName -Filter "LenovoVantageService.exe" -File -Recurse -ErrorAction Stop | Select-Object -Last 1
        if ($vantageServiceFile)
        {
            # Extract the version information
            $serviceVersion = [version]($vantageServiceFile.VersionInfo.FileVersion).Trim()
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
    if ($serviceVersion -lt $minServiceVersion)
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
# Check for the Lenovo Vantage Addins directory
try
{
    $addinsPath = "$env:ProgramData\Lenovo\Vantage\Addins"
    if (Test-Path -Path $addinsPath -PathType Container)
    {
        Write-Output "Lenovo Vantage Addins directory found at $addinsPath."
    }
    else
    {
        Write-Output "Lenovo Vantage Addins directory not found at $addinsPath."
        exit 1
    }
}
catch
{
    Write-Output "Failed to check Lenovo Vantage Addins directory. Error: $($_.Exception.Message)"
    exit 1
}
# Check for SUHelper.exe and its version (if enabled)
if ($checkSUHelper)
{
    try
    {
        # Get the SUHelper executable
        $suHelperFile = Get-Item -Path "$env:ProgramFiles\Lenovo\SUHelper\SUHelper.exe" -ErrorAction SilentlyContinue
        # Check if the file exists before proceeding
        if ($suHelperFile)
        {
            $suHelperVersion = [version]($suHelperFile.VersionInfo.FileVersion).Trim()
			if ($suHelperVersion -lt $minSUHelperVersion)
			{
				Write-Output "Lenovo SUHelper is outdated (found version $suHelperVersion, required minimum $minSUHelperVersion)."
				exit 1
			}
			else
			{
				Write-Output "Lenovo SUHelper is up-to-date (installed version: $suHelperVersion, required minimum: $minSUHelperVersion)."
			}
        }
        else
        {
            Write-Output "Lenovo SUHelper was not found at $env:ProgramFiles\Lenovo\SUHelper\SUHelper.exe."
            exit 1
        }
    }
    catch
    {
        Write-Output "Failed to retrieve Lenovo SUHelper version. Error: $($_.Exception.Message)"
        exit 1
    }
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
