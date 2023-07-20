<#

.SYNOPSIS
    Create a new Win32 application for Commercial Vantage.

.PARAMETER Tenant
    Specify the Azure tenant name, or ID, e.g. tenant.onmicrosoft.com or <GUID>

.PARAMETER PackagePath
    Specify the path to the Commercial Vantage zip.

.PARAMETER DetectionScriptFile
    Specify the path to the Commercial Vantage detection script file.

.EXAMPLE
    .\New-CommercialVantageWin32.ps1 -Tenant tenant.onmicrosoft.com -PackagePath "C:\LenovoCommercialVantage_10.2208.22.0_v3.zip" -DetectionScriptFile "C:\Detect-CommercialVantage.ps1"

.NOTES
    Author:     Philip Jorgensen
    Created:    2022-09-15
    Change:     2023-03-10 - Switch to hash table splatting and added logic for vX package versioning
    Change:     2023-07-20 - Update MinSupportedOs value
    

#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [parameter(Mandatory = $true, HelpMessage = "Specify the Azure tenant name.")]
    [ValidateNotNullOrEmpty()]
    [string]$Tenant,

    [parameter(Mandatory = $true, HelpMessage = "Specify the path to the zip.")]
    [ValidateNotNullOrEmpty()]
    [string]$PackagePath,

    [parameter(Mandatory = $true, HelpMessage = "Specify the path to the detection script file.")]
    [ValidateNotNullOrEmpty()]
    [string]$DetectionScriptFile
)

$ErrorActionPreference = 'Stop'

# Extract zip
$Source = $PackagePath.Substring(0, $PackagePath.LastIndexOf('.'))
Expand-Archive -Path $PackagePath -DestinationPath $Source -Force

# Install IntuneWin32App module
$GalleryModule = (Find-Module -Name IntuneWin32App)
$vertemp = $GalleryModule.Version.ToString()
Write-Output "Latest version of IntuneWin32App module in Gallery is $vertemp" | Out-Host
$InstalledModule = Get-InstalledModule -Name IntuneWin32App

if ($null -eq $InstalledModule) {
    Write-Output "IntuneWin32App module not installed. Installing..." | Out-Host
    try {
        Install-Module -Name IntuneWin32App -Force
    }
    catch {
        Write-Output "Failed to install IntuneWin32App module..." | Out-Host
        Write-Output $_.Exception.Message | Out-Host; Exit 1
    }
}

try {
    # Create .intunewin file
    $intuneWinParams = @{
        SourceFolder = (Get-ChildItem -Path $Source * -Directory)
        SetupFile    = (Get-ChildItem -Path $Source -Include "setup-commercial-vantage.bat" -Recurse).Name
        OutputFolder = (Split-Path -Path $PackagePath -Parent)
    } 
    New-IntuneWin32AppPackage @intuneWinParams -Verbose

    $IntuneWinFile = Get-ChildItem -Path (Split-Path -Path $PackagePath -Parent) -Filter "*.intunewin"
    $IntuneWinMetaData = Get-IntuneWin32AppMetaData -FilePath $IntuneWinFile
}
catch {
    Write-Output $_.Exception.Message | Out-Host; Exit 1
}

########## Should not need to change anything below

# Authenticate to Graph
Connect-MSIntuneGraph -TenantID $Tenant

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
if ($Source.Split("\")[-1] -match "_v") {
    $AppVersion = "$($Source.Split('_')[1,+-1] -join "_")"
}
else {
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
Remove-Item -Path $IntuneWinFile -Force