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
    New-IntuneWin32AppPackage -SourceFolder $Source -SetupFile "setup-commercial-vantage.bat" -OutputFolder (Split-Path -Path $PackagePath -Parent) -Verbose

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
Set-Variable MinSupportedOS -Option Constant -Value 1809
Set-Variable RegistryKeyPath -Option Constant -Value 'HKEY_LOCAL_MACHINE\HARDWARE\DESCRIPTION\System\BIOS'

# Install command line
$InstallCommandLine = $IntuneWinMetaData.ApplicationInfo.Name

# Uninstall command line
$UninstallCommandLine = "C:\Windows\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File .\uninstall_vantage_v8\uninstall_all.ps1"

# Create requirement rule
$RequirementRule = New-IntuneWin32AppRequirementRule `
    -Architecture x64 `
    -MinimumSupportedWindowsRelease $MinSupportedOS

# Create requirement registry rules
$RequirementRegistryRule = New-IntuneWin32AppRequirementRuleRegistry `
    -StringComparison `
    -KeyPath $RegistryKeyPath `
    -ValueName 'SystemManufacturer' `
    -StringComparisonOperator equal `
    -StringComparisonValue 'LENOVO' `
    -Check32BitOn64System $false

# Create detection rule
$DetectionRule = New-IntuneWin32AppDetectionRuleScript `
    -ScriptFile $DetectionScriptFile `
    -EnforceSignatureCheck $false `
    -RunAs32Bit $false

# Add Win32app
Add-IntuneWin32App `
    -FilePath $IntuneWinFile `
    -DisplayName 'Commercial Vantage' `
    -Description "This package updates the UEFI BIOS (including system program and Embedded Controller program) stored in the ThinkPad computer to fix problems, add new functions, or expand functions." `
    -Publisher "Lenovo" `
    -AppVersion (Split-Path $PackagePath -Leaf).Split('_')[1] `
    -InformationURL "https://support.lenovo.com/solutions/hf003321-lenovo-vantage-for-enterprise" `
    -InstallExperience system `
    -RequirementRule $RequirementRule `
    -AdditionalRequirementRule $RequirementRegistryRule `
    -RestartBehavior basedOnReturnCode `
    -DetectionRule $DetectionRule `
    -InstallCommandLine $InstallCommandLine `
    -UninstallCommandLine $UninstallCommandLine `
    -Verbose

# Cleanup
Remove-Item -Path $IntuneWinFile -Force