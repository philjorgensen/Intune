function Write-Log
{
    param (
        [Parameter(Mandatory)]
        [string]$Message,
        [Parameter(Mandatory)]
        [string]$LogPath
    )
    $logLine = "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')]: $Message"
    try
    {
        Out-File -FilePath $LogPath -InputObject $logLine -Append -NoClobber -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Failed to write to log: $($_.Exception.Message)"
        # Fallback: Output to console to avoid silent failure
        Write-Host $logLine
    }
    Write-Verbose $logLine
}

# Initialize logging
$timeStamp = Get-Date -Format 'yyyy-MM-ddTHH_mm_ss'
$logFileName = "suHelper_$timeStamp.log"
$outputFileName = "suHelper_output_$timeStamp.log"
$LogPath = Join-Path -Path $env:ProgramData -ChildPath "Lenovo\Vantage\$logFileName"
$OutputPath = Join-Path -Path $env:ProgramData -ChildPath "Lenovo\Vantage\$outputFileName"

# Ensure log directory exists
$logDir = Split-Path $LogPath -Parent
if (-not (Test-Path $logDir))
{
    New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

# Determine Program Files path, avoiding x86 redirection
$programFilesPath = if ([IntPtr]::Size -eq 4 -and [Environment]::Is64BitOperatingSystem)
{
    "C:\Windows\Sysnative\..\Program Files"
}
else
{
    $env:ProgramFiles
}

# Define SUHelper path
$expectedPath = Join-Path -Path $programFilesPath -ChildPath "Lenovo\SUHelper"

# Verify SUHelper directory
if (-not (Test-Path -Path $expectedPath -PathType Container))
{
    Write-Log -Message "SUHelper directory not found at $expectedPath." -LogPath $LogPath
    exit 1
}

# Find SUHelper.exe
$suHelperPath = Get-ChildItem -Path $expectedPath -Recurse -Filter "SUHelper.exe" -File -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName -First 1

if (-not $suHelperPath)
{
    Write-Log -Message "SUHelper.exe not found under $expectedPath." -LogPath $LogPath
    exit 1
}

Write-Log -Message "SUHelper.exe found at $suHelperPath." -LogPath $LogPath

# Start SUHelper process
$suParams = "-autoupdate -packagetype 2 -reboottype 0,3" # Filters for only drivers and packages that do/do not require a reboot
try
{
    $process = Start-Process -FilePath $suHelperPath -ArgumentList $suParams -NoNewWindow -PassThru -RedirectStandardOutput $OutputPath -ErrorAction Stop
    Write-Log -Message "SUHelper.exe started with parameters: $suParams" -LogPath $LogPath
    Wait-Process -Id $process.Id -ErrorAction Stop

    # Check for Lenovo System Update AddIn process
    $addinProcess = Get-Process -Name "LenovoVantage-(LenovoSystemUpdateAddIn)" -ErrorAction SilentlyContinue
    if ($addinProcess)
    {
        Write-Log -Message "System Update AddIn started with Process ID: $($addinProcess.Id)" -LogPath $LogPath
        Wait-Process -Id $addinProcess.Id -ErrorAction Stop
    }
    else
    {
        Write-Log -Message "System Update AddIn process not found." -LogPath $LogPath
    }

    Write-Log -Message "System Update AddIn log is located at $env:ProgramData\Lenovo\Vantage\AddinData\LenovoSystemUpdateAddin\logs" -LogPath $LogPath
    Write-Log -Message "Lenovo Commercial Vantage update process completed." -LogPath $LogPath
}
catch
{
    Write-Log -Message "Error occurred: $($_.Exception.Message)" -LogPath $LogPath
    Write-Error -Message "Error: $($_.Exception.Message)"
    exit 1
}