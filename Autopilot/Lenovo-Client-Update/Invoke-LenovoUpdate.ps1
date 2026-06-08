#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs applicable Lenovo driver, firmware (and optionally BIOS) updates using the
    Lenovo.Client.Update (LCU) PowerShell module.

.DESCRIPTION
    Built to run unattended as a Microsoft Intune Win32 app, including during the Autopilot
    Enrollment Status Page (ESP). The script:

      * Confirms the device is a Lenovo system (exits cleanly on anything else).
      * Imports the Lenovo.Client.Update module shipped alongside this script, falling back
        to an already-installed copy. LCU is published to the PowerShell Gallery, but it is
        packaged with the app (via Save-Module) rather than installed at runtime: calling
        Install-Module in SYSTEM context during ESP depends on the NuGet provider and
        PowerShellGet bootstrapping reliably, and bundling also pins a known module version.
      * Repeatedly queries, downloads and installs applicable, silent updates until none
        remain. Multiple passes are needed because installing one driver can expose further
        applicable updates.
      * Verifies each package's Lenovo digital signature before installing (LCU default).
      * Writes a transcript log under C:\ProgramData\Lenovo\Logs.
      * Returns an Intune-aware exit code: 0 = success, 3010 = success but reboot required.

.PARAMETER IncludeBIOS
    Also install BIOS/UEFI updates. Off by default: flashing the BIOS mid-Autopilot is risky
    because it needs AC power and a controlled reboot. Enable only for targeted, AC-powered
    rollouts and detect the pending action via HKLM\Software\LenovoUpdate\BIOSUpdate.

.PARAMETER MaxRounds
    Maximum number of query/install passes. Default 3.

.PARAMETER LogDirectory
    Folder for the transcript log. Defaults to C:\ProgramData\Lenovo\Lenovo.Client.Update\Logs.

.PARAMETER SkipSignatureCheck
    Passed through to Install-LnvUpdate to bypass Lenovo signature verification.
    Not recommended; provided only for troubleshooting.

.PARAMETER ExportToWMI
    Passed through to Install-LnvUpdate to write each installed package to the ROOT\Lenovo
    WMI namespace, enabling remote/inventory reporting via SCCM, Intune or Graph.

.NOTES
    Intune Win32 app install command (force 64-bit so the module's native bits load):
        %SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-LenovoDrivers.ps1

    Place the Lenovo.Client.Update module folder next to this script before building the
    .intunewin so it ships with the app.

    Detection rule: on a successful run the script writes a marker to
    HKLM\SOFTWARE\LenovoUpdate\DriverUpdate (LastRun, LastExitCode, InstalledCount,
    FailedCount, RebootRequired). For a one-shot Autopilot pass, use a Registry rule of
    "value LastRun exists". To re-run periodically, use a custom detection script that
    only reports detected when LastRun is within your freshness window.
#>

[CmdletBinding()]
param (
    [switch]$IncludeBIOS,

    [ValidateRange(1, 10)]
    [int]$MaxRounds = 3,

    [string]$LogDirectory = "$env:ProgramData\Lenovo\Lenovo.Client.Update\Logs",

    [switch]$SkipSignatureCheck,

    [switch]$ExportToWMI
)

# --- Helpers ----------------------------------------------------------------------------
function Write-LcuLog
{
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $line = '[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}' -f (Get-Date), $Level, $Message
    switch ($Level)
    {
        'Warning' { Write-Warning $line }
        'Error' { Write-Error $line }
        default { Write-Output $line }
    }
}

function Test-LnvBiosUpdate
{
    <#
        .SYNOPSIS
        Returns $true when a package is a BIOS/UEFI/system-firmware update.

        .DESCRIPTION
        Older models report the BIOS package as Type 'BIOS'. Newer models deliver it as
        Type 'Firmware' with a title such as 'System Firmware Update Utility - 11'. Both are
        treated as BIOS-class so they are governed by -IncludeBIOS and flagged for the BIOS
        registry marker, while ordinary firmware (dock, Thunderbolt, etc.) is left alone.

        A firmware package is matched on its title (BIOS/UEFI/System Firmware Update) or on
        RebootType 5, which the module uses for the mandatory-reboot BIOS/firmware flashers.
        Scoping RebootType to Type 'Firmware' avoids catching regular drivers.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [PSObject]$Update
    )

    if ($Update.Type -eq 'BIOS') { return $true }
    if ($Update.Type -eq 'Firmware' -and
        ($Update.Title -match 'BIOS|UEFI|System Firmware Update Utility' -or $Update.RebootType -eq 5))
    {
        return $true
    }
    return $false
}

# --- Main -------------------------------------------------------------------------------
$exitCode = 0

if (-not (Test-Path -LiteralPath $LogDirectory))
{
    $null = New-Item -Path $LogDirectory -ItemType Directory -Force
}
$logFile = Join-Path -Path $LogDirectory -ChildPath ('Install-LenovoDrivers_{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
Start-Transcript -Path $logFile -Force | Out-Null

try
{
    # Only run on Lenovo hardware.
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($computerSystem.Manufacturer -notlike '*LENOVO*')
    {
        Write-LcuLog "Not a Lenovo device (manufacturer: '$($computerSystem.Manufacturer)'). Nothing to do."
        return
    }
    $model = (Get-CimInstance -ClassName Win32_ComputerSystemProduct).Version
    $machineType = $computerSystem.Model.Substring(0, 4).Trim()
    Write-LcuLog "Lenovo device detected (model: '$model', machine type: '$machineType')."

    # Import the LCU module: prefer the copy packaged with this script, then any installed copy.
    $moduleName = 'Lenovo.Client.Update'
    if (-not (Get-Module -Name $moduleName))
    {
        $localManifest = Get-ChildItem -Path $PSScriptRoot -Filter "$moduleName.psd1" -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($localManifest)
        {
            Write-LcuLog "Importing $moduleName from package: $($localManifest.FullName)"
            Import-Module -Name $localManifest.FullName -Force -ErrorAction Stop
        }
        elseif (Get-Module -Name $moduleName -ListAvailable)
        {
            Write-LcuLog "Importing installed $moduleName module."
            Import-Module -Name $moduleName -Force -ErrorAction Stop
        }
        else
        {
            throw "$moduleName module was not found next to this script or installed on the device. Package the module folder with the app."
        }
    }

    # Install in rounds: installing one update can make further updates applicable.
    # Track packages already handled this run. An update that requires a reboot stays
    # IsApplicable -and -not IsInstalled until the device actually reboots, so without this
    # guard a BIOS/firmware (or any reboot-pending) package would be reinstalled every round.
    $results = [System.Collections.Generic.List[object]]::new()
    $processed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    for ($round = 1; $round -le $MaxRounds; $round++)
    {
        Write-LcuLog "Round $round of $MaxRounds : querying available updates..."

        $updates = @(Get-LnvUpdate | Where-Object {
                $_.IsApplicable -and
                -not $_.IsInstalled -and
                $_.Installer.Unattended -and
                ($IncludeBIOS -or -not (Test-LnvBiosUpdate -Update $_)) -and
                -not $processed.Contains(('{0}|{1}' -f $_.ID, $_.Version))
            })

        Write-LcuLog "$($updates.Count) new applicable, unattended update(s) found this round."
        if ($updates.Count -eq 0) { break }

        # Download everything for this round first, then install.
        $updates | Save-LnvUpdate | Out-Null

        $index = 0
        foreach ($update in $updates)
        {
            $index++
            # Mark as handled before installing so a reboot-pending package (e.g. BIOS) is
            # not picked up and reinstalled on the next round within this same run.
            $null = $processed.Add(('{0}|{1}' -f $update.ID, $update.Version))
            Write-LcuLog "Installing $index of $($updates.Count): $($update.Title) [$($update.Type)]"

            $installParams = @{ Package = $update }
            if ($SkipSignatureCheck) { $installParams['SkipSignatureCheck'] = $true }
            if ($ExportToWMI) { $installParams['ExportToWMI'] = $true }
            if (Test-LnvBiosUpdate -Update $update) { $installParams['SaveBIOSUpdateInfoToRegistry'] = $true }

            foreach ($result in (Install-LnvUpdate @installParams))
            {
                $results.Add($result)
                $status = if ($result.Success) { 'SUCCESS' } else { "FAILED ($($result.FailureReason))" }
                Write-LcuLog "  -> $status | ExitCode=$($result.ExitCode) | PendingAction=$($result.PendingAction)"
            }
        }
    }

    # Summarize and translate to an Intune-aware exit code.
    $installed = @($results | Where-Object { $_.Success })
    $failed = @($results | Where-Object { -not $_.Success })
    $rebootStates = @('REBOOT_SUGGESTED', 'REBOOT_MANDATORY', 'SHUTDOWN')
    $rebootPending = @($installed | Where-Object { $_.PendingAction -in $rebootStates })

    Write-LcuLog "Summary: $($installed.Count) installed, $($failed.Count) failed, $($results.Count) attempted."

    if ($rebootPending.Count -gt 0)
    {
        Write-LcuLog "$($rebootPending.Count) update(s) require a reboot. Returning 3010 so Intune/ESP can reboot."
        $exitCode = 3010
    }

    # Write a detection marker alongside the module's BIOSUpdate key so the Win32 app has
    # something stable to detect against. Use the native (64-bit) hive.
    $markerKey = 'HKLM:\SOFTWARE\LenovoUpdate\DriverUpdate'
    if (-not (Test-Path -LiteralPath $markerKey))
    {
        $null = New-Item -Path $markerKey -Force
    }
    $marker = @{
        LastRun        = (Get-Date).ToString('o')
        LastExitCode   = $exitCode
        InstalledCount = $installed.Count
        FailedCount    = $failed.Count
        RebootRequired = [int]($rebootPending.Count -gt 0)
    }
    foreach ($name in $marker.Keys)
    {
        New-ItemProperty -Path $markerKey -Name $name -Value $marker[$name] -PropertyType String -Force | Out-Null
    }
    Write-LcuLog "Wrote detection marker to $markerKey (LastRun, LastExitCode, InstalledCount, FailedCount, RebootRequired)."
}
catch
{
    Write-LcuLog "Fatal error: $($_.Exception.Message)" -Level Error
    $exitCode = 1
}
finally
{
    try { Stop-Transcript | Out-Null }
    catch { Write-Verbose 'Transcript was not running.' }
}

exit $exitCode
