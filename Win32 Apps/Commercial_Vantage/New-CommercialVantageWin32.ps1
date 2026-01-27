<#
.SYNOPSIS
    Create a new Win32 application for Lenovo Commercial Vantage in Microsoft Intune.

.DESCRIPTION
    This script packages Lenovo Commercial Vantage as a Win32 app for Intune deployment, using the IntuneWin32App module and Microsoft Graph API. It supports SU Helper installation, flexible uninstall options (entire suite or app only). The tenant must be a valid GUID or a domain name ending in .com.

.PARAMETER Tenant
    Specify the Azure tenant name or ID (e.g., contoso.com, tenant.onmicrosoft.com, or GUID).

.PARAMETER ZipPath
    Specify the path to the Commercial Vantage zip file.

.PARAMETER DetectionScriptFile
    Specify the path to the detection script file.

.PARAMETER SUHelper
    Include SU Helper in the installation.

.PARAMETER UninstallAppOnly
    Uninstall only the Commercial Vantage app instead of the entire suite.

.

.EXAMPLE
    .\New-CommercialVantageWin32.ps1 -Tenant "contoso.com" -ZipPath "C:\LenovoCommercialVantage_10.2208.22.0_v3.zip" -DetectionScriptFile "C:\Detect-CommercialVantage.ps1" -SUHelper -Verbose
    Installs the full suite with SU Helper and uninstalls the entire suite.

.EXAMPLE
    .\New-CommercialVantageWin32.ps1 -Tenant "123e4567-e89b-12d3-a456-426614174000" -ZipPath "C:\LenovoCommercialVantage_10.2208.22.0_v3.zip" -DetectionScriptFile "C:\Detect-CommercialVantage.ps1" -UninstallAppOnly -Verbose
    Installs the full suite and sets the uninstall command to only uninstall the app.

.EXAMPLE
    .\New-CommercialVantageWin32.ps1 -Tenant "contoso.com" -ZipPath "C:\LenovoCommercialVantage_10.2208.22.0_v3.zip" -DetectionScriptFile "C:\Detect-CommercialVantage.ps1" -Lite -SuHelper -Verbose
    Installs only the System Update feature of Commercial Vantage and SuHelper.

.NOTES
    Author:     Philip Jorgensen
    Created:    2022-09-15
    Updated:    2025-10-21
    Filename:   New-CommercialVantageWin32.ps1

    Version history:
    1.0.0 - (2022-09-15) Script created
    1.1.0 - (2023-03-10) Added hash table splatting and vX package versioning
    1.2.0 - (2023-07-20) Updated MinSupportedOs value
    1.3.0 - (2024-09-05) Added SUHelper parameter, updated Graph authentication
    2.0.0 - (2025-07-23) Script redesign for VantageInstaller.exe
                         Updated tenant validation to support GUIDs and any valid domain name
                         Update install command to use VantageInstaller.exe
                         Update uninstall command to use VantageInstaller.exe, added UninstallAppOnly parameter
    2.1.1 - (2025-08-15) Add -Lite parameter logic to install only System Update feature (https://docs.lenovocdrt.com/guides/cv/commercial_vantage/#using-vantageinstallerexe)
    2.1.2 - (2025-01-27) Change version logic due to new timestamping during zip extraction

    Requires a Microsoft Entra app registration with DeviceManagementApps.ReadWrite.All permissions.
    Reference: https://github.com/MSEndpointMgr/IntuneWin32App/issues/156
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Specify the Azure tenant name or ID (e.g., contoso.com or GUID).")]
    [ValidateScript({
            if ($_ -match "^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$" -or
                $_ -match "^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+com$")
            {
                $true
            }
            else
            {
                throw "Tenant must be a valid GUID (e.g., 123e4567-e89b-12d3-a456-426614174000) or a domain name ending in .com (e.g., contoso.com)."
            }
        })]
    [string]$Tenant,

    [Parameter(Mandatory = $true, HelpMessage = "Specify the path to the zip file.")]
    [ValidateScript({ Test-Path $_ -PathType Leaf -Include "*.zip" })]
    [string]$ZipPath,

    [Parameter(Mandatory = $true, HelpMessage = "Specify the path to the detection script file.")]
    [ValidateScript({ Test-Path $_ -PathType Leaf -Include "*.ps1" })]
    [string]$DetectionScriptFile,

    [Parameter(Mandatory = $false, HelpMessage = "Include SU Helper in the installation.")]
    [switch]$SUHelper,

    [Parameter(Mandatory = $false, HelpMessage = "Only System Update feature will be installed.")]
    [switch]$Lite,

    [Parameter(Mandatory = $false, HelpMessage = "Uninstall only the Commercial Vantage app instead of the entire suite.")]
    [switch]$UninstallAppOnly
)

# Configuration
$Config = @{
    ClientId        = "" # Set this to your Intune app registration Client ID
    ClientSecret    = "" # Set this to your Intune app registration Client Secret
    MinSupportedOS  = "w10_1809"
    RegistryKeyPath = "HKEY_LOCAL_MACHINE\HARDWARE\DESCRIPTION\System\BIOS"
    InformationURL  = "https://support.lenovo.com/solutions/hf003321-lenovo-vantage-for-enterprise"
    SetupFile       = "VantageInstaller.exe"
    DisplayName     = "Commercial Vantage"
    Publisher       = "Lenovo"
    Description     = "This package updates the UEFI BIOS (including system program and Embedded Controller program) stored in the ThinkPad computer to fix problems, add new functions, or expand functions."
}

# Function to install or update a module
function Install-RequiredModule
{
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )
    Write-Output "Checking $ModuleName module..."
    $galleryModule = Find-Module -Name $ModuleName -ErrorAction Stop
    $installedModule = Get-InstalledModule -Name $ModuleName -ErrorAction SilentlyContinue

    Write-Output "Latest $ModuleName version in gallery: $($galleryModule.Version)"
    if ($null -eq $installedModule)
    {
        Write-Output "Installing $ModuleName..."
        try
        {
            Install-Module -Name $ModuleName -Scope AllUsers -Force -ErrorAction Stop
            Write-Output "Installed $ModuleName successfully."
        }
        catch
        {
            Write-Output "Failed to install $ModuleName. Error: $($_.Exception.Message)"
            throw
        }
    }
    elseif ($installedModule.Version -lt $galleryModule.Version)
    {
        Write-Output "Updating $ModuleName from $($installedModule.Version) to $($galleryModule.Version)..."
        try
        {
            Update-Module -Name $ModuleName -Scope AllUsers -Force -ErrorAction Stop
            Write-Output "Updated $ModuleName successfully."
        }
        catch
        {
            Write-Output "Failed to update $ModuleName. Error: $($_.Exception.Message)"
            throw
        }
    }
    else
    {
        Write-Output "$ModuleName is up to date."
    }
}

# Main script logic
try
{
    # Validate environment variables
    if (-not $Config.ClientId -or -not $Config.ClientSecret)
    {
        Write-Output "ClientId or ClientSecret variables not set."
        throw "Set the ClientId and ClientSecret variables."
    }

    # Extract zip file
    $source = $ZipPath -replace '\.zip$', ''
    Write-Output "Extracting $ZipPath to $source..."
    Expand-Archive -Path $ZipPath -DestinationPath $source -Force -ErrorAction Stop
    Write-Output "Extracted successfully."

    # Install IntuneWin32App module
    Install-RequiredModule -ModuleName "IntuneWin32App"

    # Create .intunewin package
    $intuneWinParams = @{
        SourceFolder = $source
        SetupFile    = $Config.SetupFile
        OutputFolder = Split-Path -Path $ZipPath -Parent
    }
    Write-Output "Creating .intunewin package..."
    $intuneWinFile = New-IntuneWin32AppPackage @intuneWinParams -Verbose -ErrorAction Stop
    if (-not $intuneWinFile -or -not $intuneWinFile.Path -or -not (Test-Path $intuneWinFile.Path))
    {
        Write-Output "Failed to create .intunewin package. Ensure the source folder and setup file are valid."
        throw "Invalid or missing .intunewin file."
    }
    Write-Output "Created .intunewin package: $($intuneWinFile.Path)"

    # Get metadata
    $intuneWinMetaData = Get-IntuneWin32AppMetaData -FilePath $intuneWinFile.Path -ErrorAction Stop

    # Authenticate to Graph
    Write-Output "Authenticating to Microsoft Graph..."
    Connect-MSIntuneGraph -TenantID $Tenant -ClientID $Config.ClientId -ClientSecret $Config.ClientSecret -ErrorAction Stop
    Write-Output "Authenticated successfully."

    # Install command line
    $installCommandLine = "$($intuneWinMetaData.ApplicationInfo.Name) Install"
    if ($Lite) {
        $installCommandLine += " -Lite"
    } else {
        $installCommandLine += " -Vantage"
    }
    if ($SUHelper)
    {
        $installCommandLine += " -SuHelper"
    }

    # Uninstall command line
    $uninstallCommandLine = "$($intuneWinMetaData.ApplicationInfo.Name) Uninstall -Vantage"
    if ($UninstallAppOnly)
    {
        $uninstallCommandLine = "$($intuneWinMetaData.ApplicationInfo.Name) Uninstall -AppOnly"
    }

    # Create requirement rules
    $reqRuleParams = @{
        Architecture                   = "x64"
        MinimumSupportedWindowsRelease = $Config.MinSupportedOS
    }
    $requirementRule = New-IntuneWin32AppRequirementRule @reqRuleParams

    $regRuleParams = @{
        StringComparison         = $true
        KeyPath                  = $Config.RegistryKeyPath
        ValueName                = "SystemManufacturer"
        StringComparisonOperator = "equal"
        StringComparisonValue    = "LENOVO"
        Check32BitOn64System     = $false
    }
    $requirementRegistryRule = New-IntuneWin32AppRequirementRuleRegistry @regRuleParams

    # Create detection rule
    $detectParams = @{
        ScriptFile            = $DetectionScriptFile
        EnforceSignatureCheck = $false
        RunAs32Bit            = $false
    }
    $detectionRule = New-IntuneWin32AppDetectionRuleScript @detectParams

    # Parse app version
    $sourceFileBase = [System.IO.Path]::GetFileNameWithoutExtension($source)
    $appVersion = $sourceFileBase -replace '^.*_', '' -replace '\.\d{14}$', ''

    Write-Output "Parsed app version: $appVersion"

    # Add Win32 App
    $appParams = @{
        FilePath                  = $intuneWinFile.Path
        DisplayName               = $Config.DisplayName
        Description               = $Config.Description
        Publisher                 = $Config.Publisher
        AppVersion                = $appVersion
        InformationURL            = $Config.InformationURL
        InstallExperience         = "system"
        RequirementRule           = $requirementRule
        AdditionalRequirementRule = $requirementRegistryRule
        RestartBehavior           = "basedOnReturnCode"
        DetectionRule             = $detectionRule
        InstallCommandLine        = $installCommandLine
        UninstallCommandLine      = $uninstallCommandLine
    }
    Write-Output "Adding Win32 app to Intune..."
    Add-IntuneWin32App @appParams -Verbose -ErrorAction Stop
    Write-Output "Win32 app added successfully."
}
catch
{
    Write-Output "Error occurred: $($_.Exception.Message)"
    switch ($_.Exception.HResult)
    {
        0x80070002 { Write-Output "File not found error." }
        0x80070570 { Write-Output "File corrupted or inaccessible." }
        default { Write-Output "Unexpected error: $($_.Exception.HResult)" }
    }
    throw
}
finally
{
    # Cleanup
    if (Test-Path $source)
    {
        Write-Output "Cleaning up temporary files..."
        Remove-Item -Path $source -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output "Cleanup completed."
    }
    if ($intuneWinFile -and (Test-Path $intuneWinFile.Path))
    {
        Remove-Item -Path $intuneWinFile.Path -Force -ErrorAction SilentlyContinue
        Write-Output "Removed .intunewin file."
    }
}
