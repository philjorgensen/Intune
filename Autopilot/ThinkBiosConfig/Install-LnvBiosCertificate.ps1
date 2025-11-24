# Install BIOS Certificate (Dependency App)
# Exit: 1 = failed (triggers main app retry), 1641 = success + reboot

$ErrorActionPreference = 'Stop'

# === Log File ===
$LogFile = "$env:ProgramData\Lenovo\BIOSCertificates\Logs\BIOSCertInstall.log"
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
Write-Log "=== LENOVO BIOS CERTIFICATE INSTALL STARTED ===" 'INFO'

# --- Paths ---
$ModulePath = Join-Path $PSScriptRoot 'Lenovo.BIOS.Certificates\*\*.psd1'
$CertFilePath = Join-Path $PSScriptRoot '.\*.pem'

# --- Certificate Password ---
$CertPassword = 'temppassword'  # Replace with temporary BIOS password set at factory

# === Registry Tattoo Settings ===
$RegPath = 'HKLM:\SOFTWARE\Lenovo\BIOSConfigDeployment'
$RegCertStatus = 'CertStatus'
$RegLastCert = 'LastCertInstall'
$RegCertName = 'LastCertFile'

# -------------------------------------------------
# 1. Load Lenovo Certificates Module
# -------------------------------------------------
try
{
    $ModuleFile = Get-Item $ModulePath | Select-Object -First 1
    if (-not $ModuleFile) { throw "No .psd1 module found in $ModulePath" }

    Import-Module $ModuleFile.FullName -Force
    Write-Log "Loaded module: $($ModuleFile.Directory.Name)" 'SUCCESS'
}
catch
{
    Write-Log "Failed to load BIOS module: $($_.Exception.Message)" 'ERROR'
    try
    {
        if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
        Set-ItemProperty -Path $RegPath -Name $RegCertStatus -Value 'Failed' -Type String -Force
        Set-ItemProperty -Path $RegPath -Name 'LastError' -Value "Module load failed: $($_.Exception.Message)" -Type String -Force
    }
    catch { Write-Log "Could not write failure tattoo" 'WARN' }
    exit 1
}

# -------------------------------------------------
# 2. Verify Certificate File
# -------------------------------------------------
if (-not (Test-Path $CertFilePath -PathType Leaf))
{
    $msg = "Certificate file not found: $CertFilePath"
    Write-Log $msg 'ERROR'
    try
    {
        if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
        Set-ItemProperty -Path $RegPath -Name $RegCertStatus -Value 'Failed' -Type String -Force
        Set-ItemProperty -Path $RegPath -Name 'LastError' -Value $msg -Type String -Force
    }
    catch { Write-Log "Could not write failure tattoo." 'WARN' }
    exit 1
}
Write-Log "Found certificate: $CertFilePath" 'INFO'

# -------------------------------------------------
# 3. Install Certificate
# -------------------------------------------------
try
{
    $Result = Set-LnvBiosCertificate -CertFile $CertFilePath -Pass $CertPassword
    Write-Log "Certificate installation command executed." 'INFO'

    if ($null -eq $Result)
    {
        $msg = "No result returned from Set-LnvBiosCertificate"
        Write-Log $msg 'ERROR'
        throw $msg
    }

    $returnVal = $Result.ReturnValue

    Write-Log "Result: ReturnValue='$returnVal' | $env:COMPUTERNAME'" 'INFO'

    if ($returnVal -eq 'Success')
    {
        Write-Log "BIOS certificate installed successfully." 'SUCCESS'

        # === Tattoo Success ===
        try
        {
            if (-not (Test-Path $RegPath))
            {
                New-Item -Path $RegPath -Force | Out-Null
                Write-Log "Created registry path: $RegPath" 'INFO'
            }
            $certName = (Get-Item $CertFilePath).Name
            Set-ItemProperty -Path $RegPath -Name $RegCertStatus -Value 'Installed' -Type String -Force
            Set-ItemProperty -Path $RegPath -Name $RegLastCert -Value (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') -Type String -Force
            Set-ItemProperty -Path $RegPath -Name $RegCertName -Value $certName -Type String -Force
            Write-Log "Registry tattoo: CertStatus='Installed', LastCertFile='$certName'" 'SUCCESS'
        }
        catch
        {
            Write-Log "Failed to write success tattoo: $($_.Exception.Message)" 'WARN'
        }

        Write-Log "=== CERTIFICATE INSTALL COMPLETE (Exit 1641) ===" 'SUCCESS'
        # Only on first install, hard reboot is required to convert to certificate-based auth.
        exit 1641
    }
    else
    {
        $msg = "CERTIFICATE INSTALL FAILED. ReturnValue='$returnVal'"
        Write-Log $msg 'ERROR'

        # === Tattoo Failure ===
        try
        {
            if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
            Set-ItemProperty -Path $RegPath -Name $RegCertStatus -Value 'Failed' -Type String -Force
            Set-ItemProperty -Path $RegPath -Name 'LastError' -Value $msg -Type String -Force
        }
        catch { Write-Log "Could not write failure tattoo" 'WARN' }

        exit 1
    }
}
catch
{
    Write-Log "EXCEPTION during certificate install: $($_.Exception.Message)" 'ERROR'

    # === Tattoo Exception ===
    try
    {
        if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
        Set-ItemProperty -Path $RegPath -Name $RegCertStatus -Value 'Failed' -Type String -Force
        Set-ItemProperty -Path $RegPath -Name 'LastError' -Value "Exception: $($_.Exception.Message)" -Type String -Force
    }
    catch { Write-Log "Could not write exception tattoo" 'WARN' }

    exit 1
}