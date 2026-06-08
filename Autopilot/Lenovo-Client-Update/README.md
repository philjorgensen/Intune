# Lenovo Client Update Win32 App

Installs applicable Lenovo driver, firmware, and (optionally) BIOS updates using the [Lenovo.Client.Update](https://docs.lenovocdrt.com/guides/lcu/) (LCU) PowerShell module, wrapped as a Win32 app for unattended deployment with Microsoft Intune — including during Autopilot for [pre-provisioned deployment](https://learn.microsoft.com/autopilot/pre-provision).

## Requirements

- Lenovo hardware (the script exits cleanly on any other manufacturer)
- The `Lenovo.Client.Update` module folder packaged alongside the script (via `Save-Module`)
- [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool) to build the `.intunewin`
- Runs as SYSTEM in 64-bit PowerShell (use the `Sysnative` path in the install command)

## Files

**Invoke-LenovoUpdate.ps1**
- Confirms the device is a Lenovo system, then imports LCU from the copy packaged next to the script (falling back to an installed copy)
- Queries, downloads, and installs applicable **silent** updates in repeated passes until none remain — deduplicating per package so a reboot-pending update isn't reinstalled each round
- Verifies each package's Lenovo digital signature before installing (LCU default)
- Writes a transcript log under `C:\ProgramData\Lenovo\Lenovo.Client.Update\Logs`
- Returns an Intune-aware exit code (`0` success, `3010` reboot required, `1` fatal error) and writes a detection marker to `HKLM\SOFTWARE\LenovoUpdate\DriverUpdate`

## Parameters

| Parameter | Required | Description |
|---|---|---|
| `-IncludeBIOS` | No | Also install BIOS/UEFI/system-firmware updates. Off by default; enable only for targeted, AC-powered rollouts. |
| `-MaxRounds` | No | Maximum query/install passes (1–10). Default `3`. |
| `-LogDirectory` | No | Transcript log folder. Defaults to `C:\ProgramData\Lenovo\Lenovo.Client.Update\Logs`. |
| `-SkipSignatureCheck` | No | Bypass Lenovo signature verification. Not recommended; troubleshooting only. |
| `-ExportToWMI` | No | Write each installed package to the `ROOT\Lenovo` WMI namespace for inventory reporting. |

## Packaging

Stage the module and script into a source directory, then build the `.intunewin`:

```powershell
# Bundle the LCU module next to the script
Save-Module -Name Lenovo.Client.Update -Path "C:\Source\IntuneWin32\LCU"
# (copy Invoke-LenovoUpdate.ps1 into C:\Source\IntuneWin32\LCU)

# Build the package
IntuneWinAppUtil.exe -c "C:\Source\IntuneWin32\LCU" -s Invoke-LenovoUpdate.ps1 -o "C:\Source\IntuneWin32\" -q
```

## Intune configuration

| Setting | Value |
|---|---|
| **Install command** | `%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Invoke-LenovoUpdate.ps1 -IncludeBIOS -ExportToWMI` |
| **Uninstall command** | `%SystemRoot%\Sysnative\cmd.exe /c reg delete "HKLM\SOFTWARE\LenovoUpdate" /f` |
| **Install behavior** | System |
| **Device restart behavior** | Determine behavior based on return codes (so `3010` is honored) |
| **Requirements** | 64-bit; minimum OS to match your fleet |
| **Detection rule** | Registry — key `HKEY_LOCAL_MACHINE\SOFTWARE\LenovoUpdate\DriverUpdate`, value `LastRun`, **Value exists** |

> `Sysnative` is required. If a 32-bit PowerShell launches the script, the LCU module's native components fail to load.

## Deployment

Assign to a **device** group and target **Autopilot pre-provisioning** (the technician phase), where the device is wired, on AC power, and unattended. Keep it out of the ESP blocking-apps selection so it doesn't hold up the user ESP — the work is already done during pre-provisioning.

See the full write-up: [Current Drivers, Firmware, and BIOS During Autopilot Pre-Provisioning With Intune and LCU](https://blog.lenovocdrt.com/autopilot-pre-provisioning-current-drivers-firmware-bios-lcu/).
