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
$suHelperPath = Join-Path -Path "$programFilesPath\Lenovo\SUHelper" -ChildPath "SUHelper.exe"

# Check if SUHelper.exe exists
if (-not (Test-Path $suHelperPath -PathType Leaf))
{
    Write-Output "SUHelper.exe not found at $suHelperPath."
    exit 0
}

# Construct file path using Join-Path
$filePath = Join-Path -Path "$($env:ProgramData)\Lenovo\Vantage\AddinData\LenovoSystemUpdateAddin\session" -ChildPath "update_history.txt"
$thresholdDays = 30 # Adjust the threshold as needed

try
{
    # Check if the file exists
    if (Test-Path -Path $filePath -PathType Leaf)
    {
        # Get the file's properties
        $file = Get-ChildItem -Path $filePath -ErrorAction Stop
        $lastModified = $file.LastWriteTime
        $currentDate = Get-Date
        $daysSinceModified = ($currentDate - $lastModified).Days

        # Check if the file is older than 30 days
        if ($daysSinceModified -gt $thresholdDays)
        {
            Write-Output "30+ days since last check for updates. Trigger SUHelper."
            exit 1
        }
        else
        {
            Write-Output "Last update check was within the last 30 days. No action needed."
            exit 0
        }
    }
    else
    {
        Write-Output "updates_history.txt not found. Trigger SUHelper."
        exit 1
    }
}
catch
{
    Write-Output "Error occurred: $($_.Exception.Message)"
    exit 1
}