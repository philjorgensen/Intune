$ErrorActionPreference = 'Stop'

# === Log File ===
$LogFile = "$env:ProgramData\Lenovo\BIOSCertificates\Logs\BIOSConfig.log"
$LogDir = Split-Path $LogFile -Parent
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

# === Write-Log Function ===
function Write-Log
{
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "$timestamp [$Level]: $Message"
    Add-Content -Path $LogFile -Value $logEntry -Encoding UTF8
}

# === Initial log entry ===
Write-Log "=== BIOS Configuration Started ===" 'INFO'

# --- Paths ---
$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Lenovo.BIOS.Certificates\*\*.psd1' -Resolve
$ConfigFilePath = Join-Path -Path $PSScriptRoot -ChildPath '*.ini' -Resolve

# === Registry Tattoo Settings ===
$RegPath = 'HKLM:\SOFTWARE\Lenovo\BIOSConfigDeployment'
$RegNameConfig = 'LastAppliedConfig'
$RegNameSuccess = 'LastAppliedSuccess'

# -------------------------------------------------
# 1. Hybrid Detection: Registry + WMI Fallback
# -------------------------------------------------
$CertInstalled = $false

# --- Step 1: Check Registry Tattoo ---
if (Test-Path $RegPath)
{
    try
    {
        $regProps = Get-ItemProperty -Path $RegPath

        # Debug: Log all properties
        $regProps | Get-Member -MemberType NoteProperty | ForEach-Object {
            Write-Log "Registry entry: $($_.Name) = '$($regProps.($_.Name))'" 'INFO'
        }

        if ($regProps.CertStatus -eq 'Installed')
        {
            Write-Log "Registry confirms certificate installed (CertStatus=Success)" 'SUCCESS'
            $CertInstalled = $true
        }
        else
        {
            Write-Log "Registry exists but CertStatus is not Success (found: '$($regProps.CertStatus)')" 'WARN'
        }
    }
    catch
    {
        Write-Log "Failed to read registry key $($RegPath): $($_.Exception.Message)" 'WARN'
    }
}
else
{
    Write-Log "Registry path $RegPath does not exist yet." 'INFO'
}

# --- Step 2: WMI Fallback ---
if (-not $CertInstalled)
{
    try
    {
        $BiosPassword = Get-CimInstance -Namespace root\WMI -ClassName Lenovo_BiosPasswordSettings
        $PasswordState = $BiosPassword.PasswordState
        Write-Log "WMI PasswordState: $PasswordState" 'INFO'

        # Password State 128 indicates certificate-based authentication (https://docs.lenovocdrt.com/ref/bios/wmi/wmi_guide/#detecting-password-state)
        if ($PasswordState -eq 128)
        {
            Write-Log "WMI confirms certificate installed (PasswordState=128)" 'SUCCESS'
            $CertInstalled = $true

            # Sync registry
            try
            {
                if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
                Set-ItemProperty -Path $RegPath -Name 'CertStatus' -Value 'Success' -Type String -Force
                Set-ItemProperty -Path $RegPath -Name 'LastCertInstall' -Value (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') -Type String -Force
                Write-Log "Updated registry tattoo from WMI detection" 'INFO'
            }
            catch
            {
                Write-Log "Could not update registry from WMI: $($_.Exception.Message)" 'WARN'
            }
        }
    }
    catch
    {
        Write-Log "WMI query failed: $($_.Exception.Message)" 'WARN'
    }
}

# --- Step 3: Final Decision ---
if (-not $CertInstalled)
{
    $msg = "BIOS certificate not detected (registry or WMI). Waiting for dependency app."
    Write-Log $msg 'ERROR'
    try
    {
        if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
        Set-ItemProperty -Path $RegPath -Name 'Status' -Value 'Failed' -Type String -Force
        Set-ItemProperty -Path $RegPath -Name 'LastError' -Value $msg -Type String -Force
    }
    catch { }
    Write-Log "Exiting 1 - will retry after cert app" 'INFO'
    exit 1
}

Write-Log "Certificate confirmed. Proceeding with BIOS config." 'SUCCESS'

# -------------------------------------------------
# 2. Import Lenovo BIOS Module
# -------------------------------------------------
try
{
    $Module = Import-Module -Name $ModulePath -PassThru -Force
    Write-Log "Successfully imported module: $($Module.Name)" 'SUCCESS'
}
catch
{
    Write-Log "Failed to import Lenovo BIOS module from '$ModulePath': $($_.Exception.Message)" 'ERROR'
    exit 1
}

# -------------------------------------------------
# 3. Verify Config File Exists
# -------------------------------------------------
if (-not (Test-Path -Path $ConfigFilePath -PathType Leaf))
{
    Write-Log "Configuration file not found: '$ConfigFilePath'" 'ERROR'
    exit 1
}
Write-Log "Found config file: $ConfigFilePath" 'INFO'

# -------------------------------------------------
# 4. Submit BIOS Config & Validate ALL Results
# -------------------------------------------------
try
{
    $Result = Submit-LnvBiosConfigFile -ConfigFile $ConfigFilePath
    Write-Log "BIOS configuration file submitted: '$ConfigFilePath'" 'INFO'
    Write-Log "Refer to BiosCerts.log under %ProgramData%\Lenovo\BIOSCertificates\Logs" 'INFO'

    if ($Result -and $Result.Count -gt 0)
    {
        $allSuccess = $true
        $failureDetails = @()
        $successCount = 0

        foreach ($setting in $Result)
        {
            $returnVal = if ($setting.ReturnValue) { $setting.ReturnValue } else { 'Unknown' }
            Write-Log "  -> Setting result Betting: ReturnValue='$returnVal' | $env:COMPUTERNAME" 'INFO'

            if ($returnVal -eq 'Success')
            {
                $successCount++
            }
            else
            {
                $allSuccess = $false
                $failureDetails += "ReturnValue='$returnVal'"
            }
        }

        if ($allSuccess)
        {
            Write-Log "All $($Result.Count) settings applied (ReturnValue: Success)" 'SUCCESS'

            # === Tattoo Registry on Success ===
            try
            {
                if (-not (Test-Path $RegPath))
                {
                    New-Item -Path $RegPath -Force | Out-Null
                    Write-Log "Created registry path: $RegPath" 'INFO'
                }
                $configName = (Get-Item $ConfigFilePath).Name
                Set-ItemProperty -Path $RegPath -Name $RegNameConfig -Value $configName -Type String -Force
                Set-ItemProperty -Path $RegPath -Name $RegNameSuccess -Value (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') -Type String -Force
                Set-ItemProperty -Path $RegPath -Name 'Status' -Value 'Success' -Type String -Force
                Write-Log "Registry tattoo applied: $RegNameConfig='$configName', Status='Success'" 'SUCCESS'
            }
            catch
            {
                Write-Log "Failed to write success tattoo: $($_.Exception.Message)" 'WARN'
            }
        }
        else
        {
            $msg = "PARTIAL FAILURE: $successCount/$($Result.Count) succeeded. Failed: $($failureDetails -join '; ')"
            Write-Log $msg 'ERROR'
            try
            {
                if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
                Set-ItemProperty -Path $RegPath -Name 'Status' -Value 'Failed' -Type String -Force
                Set-ItemProperty -Path $RegPath -Name 'LastError' -Value $msg -Type String -Force
            }
            catch { Write-Log "Failed to write failure tattoo" 'WARN' }
            Write-Log "Exiting with code 1 (partial failure)" 'INFO'
            exit 1
        }
    }
    else
    {
        $msg = "No results returned from Submit-LnvBiosConfigFile"
        Write-Log $msg 'ERROR'
        try
        {
            if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
            Set-ItemProperty -Path $RegPath -Name 'Status' -Value 'Failed' -Type String -Force
            Set-ItemProperty -Path $RegPath -Name 'LastError' -Value $msg -Type String -Force
        }
        catch { Write-Log "Failed to write failure tattoo" 'WARN' }
        exit 1
    }
}
catch
{
    Write-Log "EXCEPTION in Submit-LnvBiosConfigFile: $($_.Exception.Message)" 'ERROR'
    try
    {
        if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
        Set-ItemProperty -Path $RegPath -Name 'Status' -Value 'Failed' -Type String -Force
        Set-ItemProperty -Path $RegPath -Name 'LastError' -Value $_.Exception.Message -Type String -Force
    }
    catch { Write-Log "Failed to write exception tattoo" 'WARN' }
    exit 1
}

# -------------------------------------------------
# 5. Success → Request Reboot
# -------------------------------------------------
Write-Log "=== BIOS CONFIG COMPLETED SUCCESSFULLY ===" 'SUCCESS'
Write-Log "Exit code: 1641 (reboot required to apply settings)" 'INFO'
exit 1641