# Commercial Vantage Win32 App

Packages and deploys [Lenovo Commercial Vantage](https://support.lenovo.com/solutions/hf003321-lenovo-vantage-for-enterprise) as a Win32 app in Microsoft Intune using the [IntuneWin32App](https://github.com/MSEndpointMgr/IntuneWin32App) module.

## Requirements

- Microsoft Entra app registration with **DeviceManagementApps.ReadWrite.All** permissions
- [IntuneWin32App](https://github.com/MSEndpointMgr/IntuneWin32App) PowerShell module (installed automatically if not present)
- Commercial Vantage zip package (e.g., `LenovoCommercialVantage_20.2511.24.0.zip`)

## Files

**New-CommercialVantageWin32.ps1**
- Extracts the zip, creates the `.intunewin` package, and uploads the Win32 app to Intune
- Configures install/uninstall commands, requirement rules, and detection rule automatically
- Targets x64 devices running Windows 10 1809 or later with `SystemManufacturer = LENOVO`

**Detect-CommercialVantage.ps1**
- Used as the Win32 app detection script in Intune
- Verifies LenovoVantageService.exe version, the Vantage Addins directory, and the Commercial Vantage APPX package version

## Parameters

| Parameter | Required | Description |
|---|---|---|
| `-Tenant` | Yes | Azure tenant name (e.g., `contoso.com`) or GUID |
| `-ZipPath` | Yes | Path to the Commercial Vantage `.zip` file |
| `-DetectionScriptFile` | Yes | Path to `Detect-CommercialVantage.ps1` |
| `-SUHelper` | No | Include SU Helper in the installation |
| `-Lite` | No | Install only the System Update feature |
| `-UninstallAppOnly` | No | Uninstall only the app instead of the entire suite |

## Usage

```powershell
# Full suite with SU Helper
.\New-CommercialVantageWin32.ps1 -Tenant "contoso.com" -ZipPath "C:\LenovoCommercialVantage_20.2511.24.0.zip" -DetectionScriptFile "C:\Detect-CommercialVantage.ps1" -SUHelper -Verbose

# Full suite, uninstall app only
.\New-CommercialVantageWin32.ps1 -Tenant "contoso.com" -ZipPath "C:\LenovoCommercialVantage_20.2511.24.0.zip" -DetectionScriptFile "C:\Detect-CommercialVantage.ps1" -UninstallAppOnly -Verbose

# Lite install (System Update feature only) with SU Helper
.\New-CommercialVantageWin32.ps1 -Tenant "contoso.com" -ZipPath "C:\LenovoCommercialVantage_20.2511.24.0.zip" -DetectionScriptFile "C:\Detect-CommercialVantage.ps1" -Lite -SUHelper -Verbose
```
