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

.PARAMETER UseAzCopy
    Specify the UseAzCopy parameter switch when adding an application with source files larger than 500MB. 

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
    Updated:    2026-02-25
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
    2.2.0 - (2026-02-25) Fix ValidateScript extension validation for ZipPath and DetectionScriptFile
                         Update app Description to accurately describe Commercial Vantage
                         Remove SupportsShouldProcess from CmdletBinding
                         Replace Write-Output with Write-Verbose/Write-Warning throughout
                         Fix inconsistent brace style in install command logic

    Requires a Microsoft Entra app registration with DeviceManagementApps.ReadWrite.All permissions.
    Reference: https://github.com/MSEndpointMgr/IntuneWin32App/issues/156
    IntuneWin32App module by Nickolaj Andersen: https://github.com/MSEndpointMgr/IntuneWin32App

#>

[CmdletBinding()]
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
    [ValidateScript({ (Test-Path $_ -PathType Leaf) -and ([System.IO.Path]::GetExtension($_) -eq '.zip') })]
    [string]$ZipPath,

    [Parameter(Mandatory = $true, HelpMessage = "Specify the path to the detection script file.")]
    [ValidateScript({ (Test-Path $_ -PathType Leaf) -and ([System.IO.Path]::GetExtension($_) -eq '.ps1') })]
    [string]$DetectionScriptFile,

    [Parameter(Mandatory = $false, HelpMessage = "Include SU Helper in the installation.")]
    [switch]$SUHelper,

    [Parameter(Mandatory = $false, HelpMessage = "Only System Update feature will be installed.")]
    [switch]$Lite,
    
    [Parameter(Mandatory = $false, HelpMessage ="Tells the script to use AzCopy.exe method for file transfer")]
    [switch]$UseAzCopy,

    [Parameter(Mandatory = $false, HelpMessage = "Uninstall only the Commercial Vantage app instead of the entire suite.")]
    [switch]$UninstallAppOnly

)

# Configuration
$Config = @{
     ClientId       = "##" # Set this to your Intune app registration Client ID
    ClientSecret    = "####" # Set this to your Intune app registration Client Secret
    MinSupportedOS  = "w10_1809"
    RegistryKeyPath = "HKEY_LOCAL_MACHINE\HARDWARE\DESCRIPTION\System\BIOS"
    InformationURL  = "https://support.lenovo.com/solutions/hf003321-lenovo-vantage-for-enterprise"
    SetupFile       = "VantageInstaller.exe"
    DisplayName     = "Commercial Vantage"
    Publisher       = "Lenovo"
    Description     = "Commercial Vantage provides a user interface for changing hardware settings, checking for Lenovo software and driver updates, and more."
}

# Function to install or update a module
function Install-RequiredModule
{
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )
    Write-Verbose "Checking $ModuleName module..."
    $galleryModule = Find-Module -Name $ModuleName -ErrorAction Stop
    $installedModule = Get-InstalledModule -Name $ModuleName -ErrorAction SilentlyContinue

    Write-Verbose "Latest $ModuleName version in gallery: $($galleryModule.Version)"
    if ($null -eq $installedModule)
    {
        Write-Verbose "Installing $ModuleName..."
        try
        {
            Install-Module -Name $ModuleName -Scope AllUsers -Force -ErrorAction Stop
            Write-Verbose "Installed $ModuleName successfully."
        }
        catch
        {
            Write-Warning "Failed to install $ModuleName. Error: $($_.Exception.Message)"
            throw
        }
    }
    elseif ($installedModule.Version -lt $galleryModule.Version)
    {
        Write-Verbose "Updating $ModuleName from $($installedModule.Version) to $($galleryModule.Version)..."
        try
        {
            Update-Module -Name $ModuleName -Scope AllUsers -Force -ErrorAction Stop
            Write-Verbose "Updated $ModuleName successfully."
        }
        catch
        {
            Write-Warning "Failed to update $ModuleName. Error: $($_.Exception.Message)"
            throw
        }
    }
    else
    {
        Write-Verbose "$ModuleName is up to date."
    }
}
$startUtc = [datetime]::UtcNow
# Main script logic
try
{
    # Validate environment variables
    if (-not $Config.ClientId -or -not $Config.ClientSecret)
    {
        Write-Warning "ClientId or ClientSecret variables not set."
        throw "Set the ClientId and ClientSecret variables."
    }

    # Extract zip file
    $zipFolder = Split-Path -Path $ZipPath -Parent
    Write-Verbose "Working Directory is $zipFolder"
    $source = $ZipPath -replace '\.zip$', ''
    Write-Verbose "Extracting $ZipPath via .NET to $source..."
   [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $source)
    #Expand-Archive -Path $ZipPath -DestinationPath $source -Force -ErrorAction Stop
    Write-Verbose "Extracted successfully."

    # Install IntuneWin32App module
    Install-RequiredModule -ModuleName "IntuneWin32App"

    # Create .intunewin package
    $intuneWinParams = @{
        SourceFolder = $source
        SetupFile    = $Config.SetupFile
        OutputFolder = Split-Path -Path $ZipPath -Parent
    }
    Write-Verbose "Creating .intunewin package..."
    $intuneWinFile = New-IntuneWin32AppPackage @intuneWinParams -Verbose -ErrorAction Stop
    if (-not $intuneWinFile -or -not $intuneWinFile.Path -or -not (Test-Path $intuneWinFile.Path))
    {
        Write-Warning "Failed to create .intunewin package. Ensure the source folder and setup file are valid."
        throw "Invalid or missing .intunewin file."
    }
    Write-Verbose "Created .intunewin package: $($intuneWinFile.Path)"

    # Get metadata
    $intuneWinMetaData = Get-IntuneWin32AppMetaData -FilePath $intuneWinFile.Path -ErrorAction Stop

    # Authenticate to Graph
    Write-Verbose "Authenticating to Microsoft Graph..."
    Connect-MSIntuneGraph -TenantID $Tenant -ClientID $Config.ClientId -ClientSecret $Config.ClientSecret -ErrorAction Stop
    Write-Verbose "Authenticated successfully."

    # Install command line
    $installCommandLine = "$($intuneWinMetaData.ApplicationInfo.Name) Install"
    if ($Lite)
    {
        $installCommandLine += " -Lite"
    }
    else
    {
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

    Write-Verbose "Parsed app version: $appVersion"

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

    Write-Verbose "Adding Win32 app to Intune..."
    
    $addAppParams = @{
            ErrorAction = 'Stop'
    }

    if ($UseAzCopy) {
    $addAppParams['UseAzCopy']         = $true
    $addAppParams['AzCopyWindowStyle'] = 'hidden'
    }

    $intuneApp = Add-IntuneWin32App @appParams @addAppParams -Verbose
    #$intuneApp = Add-IntuneWin32App @appParams -ErrorAction Stop -UseAzCopy -AzCopyWindowStyle hidden -Verbose #6>$null #-UseAzCopy -AzCopyWindowStyle hidden -UseAzCopy
    Write-Verbose "Win32 app added successfully. App ID: $($intuneApp.id)"

   <#check that we have an App ID to set Icon
   if ($intuneApp -and $intuneApp.id) {
    Write-Verbose "Looking for an App Icon in working folder"
    $iconFile = Get-ChildItem -Path $zipFolder -Filter "*.png" -File | Select-Object -First 1
    if ($iconFile) {
        Write-Verbose "Found PNG icon: $($iconFile.FullName)"
        $iconBase64 = New-IntuneWin32AppIcon -FilePath $iconFile
        Write-verbose "Converted PNG to base64"
        Set-IntuneWin32App -ID $intuneApp.id -Icon $iconBase64
        Write-Verbose "App Icon set successfully."
    }
    else {
        Write-Warning "No ICON file found in $zipFolder, attempting to retrieve from App store."
        $iconUrl = "https://store-images.s-microsoft.com/image/apps.43368.9007199266245619.fdfb1c62-4857-4684-bb35-f6ee88fcca67.ee098c14-3169-4739-b6da-da70cf9ed8ff?h=380"
        $iconPath = Join-Path -Path $zipFolder -ChildPath "VantageIcon.png"
        Invoke-WebRequest -Uri $iconUrl -OutFile $iconPath -ErrorAction Stop
        Write-Verbose "Icon downloaded to: $iconPath"

    }
}#>

if ($intuneApp -and $intuneApp.id) {
    Write-Verbose "Looking for an App Icon in working folder"
    $iconFile = Get-ChildItem -Path $zipFolder -Filter "*.png" -File | Select-Object -First 1

    if (-not $iconFile) {
        Write-Warning "No PNG found in $zipFolder, attempting to retrieve from App store."
        $iconUrl = "https://store-images.s-microsoft.com/image/apps.43368.9007199266245619.fdfb1c62-4857-4684-bb35-f6ee88fcca67.ee098c14-3169-4739-b6da-da70cf9ed8ff?h=380"
        $iconPath = Join-Path -Path $zipFolder -ChildPath "VantageIcon.png"
        Invoke-WebRequest -Uri $iconUrl -OutFile $iconPath -ErrorAction Stop

        if (Test-Path -LiteralPath $iconPath) {
            $iconSize = (Get-Item -LiteralPath $iconPath).Length
            if ($iconSize -gt 0) {
                Write-Verbose "Icon downloaded successfully: $iconPath ($iconSize bytes)"
                $iconFile = Get-Item -LiteralPath $iconPath
            }
            else {
                throw "Icon file was created but is empty: $iconPath"
            }
        }
        else {
            throw "Icon file was not created: $iconPath"
        }
    }

    if ($iconFile) {
        Write-Verbose "Found PNG icon: $($iconFile.FullName)"
        $iconBase64 = New-IntuneWin32AppIcon -FilePath $iconFile.FullName
        Write-Verbose "Converted PNG to base64"
        Set-IntuneWin32App -ID $intuneApp.id -Icon $iconBase64 -ErrorAction Stop
        Write-Verbose "App Icon set successfully."
    }
    else{
        Write-Verbose "No App Icon found successfully. Skipping setting App ICON"
    }
}
    
}
catch
{
    Write-Warning "Error occurred: $($_.Exception.Message)"
    switch ($_.Exception.HResult)
    {
        0x80070002 { Write-Warning "File not found error." }
        0x80070570 { Write-Warning "File corrupted or inaccessible." }
        default { Write-Warning "Unexpected error: $($_.Exception.HResult)" }
    }
    throw
}
finally
{
    # Cleanup
    if (Test-Path $source)
    {
        Write-Verbose "Cleaning up temporary files..."
        Remove-Item -Path $source -Recurse -Force -ErrorAction SilentlyContinue
        Write-Verbose "Cleanup completed."
    }
    if ($intuneWinFile -and (Test-Path $intuneWinFile.Path))
    {
        Remove-Item -Path $intuneWinFile.Path -Force -ErrorAction SilentlyContinue
        Write-Verbose "Removed .intunewin file."
    }

    $stopUtc = [datetime]::UtcNow

    # Calculate the total run time
    $runTime = $stopUTC - $startUTC

    # Format the runtime with hours, minutes, and seconds
    if ($runTime.TotalHours -ge 1) {
	    $runTimeFormatted = 'Duration: {0:hh} hr {0:mm} min {0:ss} sec' -f $runTime
    }
    else {
	    $runTimeFormatted = 'Duration: {0:mm} min {0:ss} sec' -f $runTime
    }

    Write-Verbose "Total Script $($runTimeFormatted)"
}

