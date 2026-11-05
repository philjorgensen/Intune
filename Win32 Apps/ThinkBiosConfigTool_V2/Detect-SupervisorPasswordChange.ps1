<#
    .SYNOPSIS
    Win32 app detection script for the supervisor password change.

    .DESCRIPTION
    Reads the latest Think BIOS Config Tool V2 log under %ProgramData%\Lenovo\ThinkBiosConfig, isolates
    the last Import-LnvPasswordChangeFile run, and confirms every step reported Success.
#>

# Define the path where the log file is located
$tbctPath = Join-Path -Path $env:ProgramData -ChildPath "Lenovo\ThinkBiosConfig"

# Find the latest log file (*.log or *.txt) in the Lenovo ThinkBiosConfig directory
$logFile = Get-ChildItem -Path $tbctPath -Filter "*.log" -Recurse -ErrorAction SilentlyContinue |
    Sort-Object -Property LastWriteTime -Descending |
    Select-Object -Last 1

if ($logFile)
{
    # Read the log file content and isolate the last run block
    $logContent = Get-Content -Path $logFile.FullName
    $lastBlockStart = ($logContent | Select-String -SimpleMatch -Pattern "Import-LnvPasswordChangeFile" | Select-Object -Last 1).LineNumber
    if ($lastBlockStart) { $logContent = $logContent[($lastBlockStart)..($logContent.Count - 1)] }

    # Define the expected success messages for each step
    $expectedSuccesses = @(
        "Targeting password type: Success",
        "Setting current password: Success",
        "Setting new password: Success",
        "Authenticating: Success",
        "Committing change: Success"
    )

    # Check if all expected success messages are present in the log
    $missing = @()
    foreach ($success in $expectedSuccesses)
    {
        if (-not ($logContent | Select-String -SimpleMatch -Pattern $success))
        {
            $missing += $success
        }
    }

    if ($missing.Count -eq 0)
    {
        Write-Output "Supervisor Password change detected as successful."
        exit 0  # Detection successful
    }
    else
    {
        Write-Output "Supervisor Password change not successful. Missing expected entries:"
        $missing | ForEach-Object { Write-Output " - $_" }
        exit 1  # Not detected
    }
}
else
{
    Write-Output "Log file not found."
    exit 1  # Not detected
}
