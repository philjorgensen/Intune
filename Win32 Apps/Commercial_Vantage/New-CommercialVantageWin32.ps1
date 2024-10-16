<#
.SYNOPSIS
    Create a new Win32 application for Commercial Vantage.

.PARAMETER Tenant
    Specify the Azure tenant name, or ID, e.g., tenant.onmicrosoft.com or <GUID>.

.PARAMETER ZipPath
    Specify the path to the Commercial Vantage zip.

.PARAMETER DetectionScriptFile
    Specify the path to the Commercial Vantage detection script file.

.PARAMETER SUHelper
    Switch to indicate whether SU Helper should be installed.

    Reference:
    https://docs.lenovocdrt.com/guides/cv/#suhelper

.EXAMPLE
    .\New-CommercialVantageWin32.ps1 -Tenant tenant.onmicrosoft.com -ZipPath "C:\LenovoCommercialVantage_10.2208.22.0_v3.zip" -DetectionScriptFile "C:\Detect-CommercialVantage.ps1" -SUHelper

.NOTES
    Author:     Philip Jorgensen
    Created:    2022-09-15
    Change:     2023-03-10 - Switch to hash table splatting and added logic for vX package versioning
    Change:     2023-07-20 - Update MinSupportedOs value
    Change:     2024-09-05 - Add SUHelper parameter. Reference change for Graph authentication, which requires a new app registration/secret.
    Filename:   New-CommercialVantageWin32.ps1

    The Microsoft Intune PowerShell application has been deprecated so you'll need to create a new app registration with appropriate permissions and update the ClientId
    Reference https://github.com/MSEndpointMgr/IntuneWin32App/issues/156
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [parameter(Mandatory = $true, HelpMessage = "Specify the Azure tenant name.")]
    [ValidateNotNullOrEmpty()]
    [string]$Tenant,

    [parameter(Mandatory = $true, HelpMessage = "Specify the path to the zip.")]
    [ValidateNotNullOrEmpty()]
    [string]$ZipPath,

    [parameter(Mandatory = $true, HelpMessage = "Specify the path to the detection script file.")]
    [ValidateNotNullOrEmpty()]
    [string]$DetectionScriptFile,

    [parameter(Mandatory = $false, HelpMessage = "Install SU Helper")]
    [switch]$SUHelper
)

# Principal variables for Graph Auth
$clientId = ''
$clientSecret = ''

#region functions
# Function to install a module if not present
function Install-RequiredModule
{
    $GalleryModule = Find-Module -Name IntuneWin32App
    $InstalledModule = Get-InstalledModule -Name IntuneWin32App -ErrorAction SilentlyContinue

    Write-Output "Latest version of IntuneWin32App module in Gallery is $($GalleryModule.Version)" | Out-Host

    if ($null -eq $InstalledModule)
    {
        Write-Output "IntuneWin32App module not installed. Installing..." | Out-Host
        try
        {
            Install-Module -Name IntuneWin32App -Scope AllUsers -Force
            Write-Output "Installation successful." | Out-Host
        }
        catch
        {
            Write-Output "Failed to install IntuneWin32App module." | Out-Host
            Write-Output $_.Exception.Message | Out-Host
            Exit 1
        }
    }
    elseif ($InstalledModule.Version -lt $GalleryModule.Version)
    {
        Write-Output "An older version of IntuneWin32App module is installed. Updating to latest version..." | Out-Host
        try
        {
            Update-Module -Name IntuneWin32App -Scope AllUsers -Force
            Write-Output "Update successful." | Out-Host
        }
        catch
        {
            Write-Output "Failed to update IntuneWin32App module." | Out-Host
            Write-Output $_.Exception.Message | Out-Host
            Exit 1
        }
    }
    else
    {
        Write-Output "IntuneWin32App module is up to date." | Out-Host
    }
}

# Function to uncomment a specific line in a .bat file
function Uncomment-BatFileLine
{
    param (
        [string]$FilePath,
        [string]$Pattern,
        [string]$Replacement
    )
    
    if (Test-Path -Path $FilePath)
    {
        try
        {
            $Content = Get-Content -Path $FilePath
            $UpdatedContent = $Content -replace $Pattern, $Replacement
            Set-Content -Path $FilePath -Value $UpdatedContent
            Write-Output "Successfully uncommented the line in $FilePath."
        }
        catch
        {
            Write-Error "Failed to update $FilePath $_"
        }
    }
    else
    {
        Write-Warning "$FilePath does not exist."
    }
}
#endregion

# Main script logic
try
{
    # Extract the zip file
    $Source = $ZipPath -replace '\.zip$', ''
    Expand-Archive -Path $ZipPath -DestinationPath $Source -Force
    Write-Output "Extracted $ZipPath to $Source."

    # Define the path to the .bat file
    $InstallBat = Get-ChildItem -Path $Source -Include "setup-commercial-vantage.bat" -Recurse

    if ($SUHelper.IsPresent)
    {
        try
        {
            Write-Output "Adjusting .bat file for SUHelper install"
            Uncomment-BatFileLine -FilePath $InstallBat.FullName -Pattern '^@REM\s*\.\\SystemUpdate\\SUHelperSetup\.exe /VERYSILENT' -Replacement '.\SystemUpdate\SUHelperSetup.exe /VERYSILENT'
        }
        catch
        {
            Write-Error -Message "Unable to change .bat file"
            continue
        }
    }

    # Install the IntuneWin32App module if not already installed
    Install-RequiredModule

    # Create the .intunewin package
    $intuneWinParams = @{
        SourceFolder = $Source
        SetupFile    = $InstallBat.Name
        OutputFolder = (Split-Path -Path $ZipPath -Parent)
    }
    New-IntuneWin32AppPackage @intuneWinParams -Verbose

    $IntuneWinFile = Get-ChildItem -Path $intuneWinParams.OutputFolder -Filter "*.intunewin"
    $IntuneWinMetaData = Get-IntuneWin32AppMetaData -FilePath $IntuneWinFile.FullName

    # Authenticate to Graph
    Connect-MSIntuneGraph -TenantID $Tenant -ClientID $clientId -ClientSecret $clientSecret -ErrorAction Stop

    # Make a constant so there are no magic numbers
    Set-Variable MinSupportedOS -Option Constant -Value w10_1809
    Set-Variable RegistryKeyPath -Option Constant -Value 'HKEY_LOCAL_MACHINE\HARDWARE\DESCRIPTION\System\BIOS'

    # Install command line
    $InstallCommandLine = $IntuneWinMetaData.ApplicationInfo.Name

    # Uninstall command line
    $UninstallCommandLine = "C:\Windows\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File .\uninstall_vantage_v8\uninstall_all.ps1"

    # Create requirement rule
    $reqRuleParams = @{
        Architecture                   = "x64"
        MinimumSupportedWindowsRelease = $MinSupportedOS
    }

    $RequirementRule = New-IntuneWin32AppRequirementRule @reqRuleParams

    # Create requirement registry rules
    $regRuleParams = @{
        StringComparison         = $true
        KeyPath                  = $RegistryKeyPath
        ValueName                = "SystemManufacturer"
        StringComparisonOperator = "equal"
        StringComparisonValue    = "LENOVO"
        Check32BitOn64System     = $false
    }

    $RequirementRegistryRule = New-IntuneWin32AppRequirementRuleRegistry @regRuleParams

    # Create detection rule
    $detectParams = @{
        ScriptFile            = $DetectionScriptFile
        EnforceSignatureCheck = $false
        RunAs32Bit            = $false
    }

    $DetectionRule = New-IntuneWin32AppDetectionRuleScript @detectParams

    <#
    Some of the dependencies related to the Vantage service may be updated, resulting in a vX package (v2,v3,v4,etc)
    This logic will set the appropriate version if a vX package is downloaded
    #>
    if ($Source.Split("\")[-1] -match "_v")
    {
        $AppVersion = "$($Source.Split('_')[1,+-1] -join "_")"
    }
    else
    {
        $AppVersion = "$($Source.Split('_')[1])"
    }

    # Add Win32 App
    $appParams = @{
        FilePath                  = $IntuneWinFile
        DisplayName               = "Commercial Vantage"
        Description               = "This package updates the UEFI BIOS (including system program and Embedded Controller program) stored in the ThinkPad computer to fix problems, add new functions, or expand functions."
        Publisher                 = "Lenovo"
        AppVersion                = $AppVersion
        InformationURL            = "https://support.lenovo.com/solutions/hf003321-lenovo-vantage-for-enterprise"
        InstallExperience         = "system"
        RequirementRule           = $RequirementRule
        AdditionalRequirementRule = $RequirementRegistryRule
        RestartBehavior           = "basedOnReturnCode"
        DetectionRule             = $DetectionRule
        InstallCommandLine        = $InstallCommandLine
        UninstallCommandLine      = $UninstallCommandLine
    }

    Add-IntuneWin32App @appParams -Verbose

    # Cleanup
    Remove-Item -Path $IntuneWinFile.FullName -Force
    Write-Output "Cleaned up temporary files."
}
catch
{
    Write-Error "An error occurred: $_"
    throw
}