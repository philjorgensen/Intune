<#
    .SYNOPSIS
    Think BIOS Config Tool Supervisor Password Update Script

    .DESCRIPTION
    This script updates the Supervisor Password (SVP) using the Think BIOS Config Tool (TBCT). This tool does not support setting an initial SVP, so it is intended to be run on devices that already have an SVP set.
    The script checks for the existence of the TBCT HTA file and a password file, creates necessary directories, and executes the TBCT to change the SVP. It also checks the log file for success and sets a status file for Intune detection.

    .NOTES
    Version: 1.0    - Initial release - 2024-07-15
    Version: 2.0    - Changed Start-Process to use ms 

#>

# Define variables
$lenovoPath = Join-Path -Path $env:ProgramData -ChildPath "Lenovo\ThinkBiosConfig"
$htaFilePath = Join-Path -Path $PSScriptRoot -ChildPath "ThinkBiosConfig.hta"
$passFilePath = (Get-ChildItem -Path $PSScriptRoot -Filter "*.ini").FullName
$secretKey = "" # Set secret key or password here
$arguments = "`"`" `"file=$passFilePath`" `"pass=$secretKey`" `"log=$lenovoPath`""
$statusFilePath = Join-Path -Path $lenovoPath -ChildPath "svp.status"

try
{
    # Check if ThinkBiosConfig.hta and password file exist
    $htaExists = Test-Path -Path $htaFilePath -PathType Leaf
    $passFileExists = Test-Path -Path $passFilePath -PathType Leaf

    if ($htaExists -and $passFileExists)
    {
        # Remove previous log file if it exists
        Get-ChildItem -Path $lenovoPath -Filter "*.txt" -ErrorAction SilentlyContinue | Remove-Item -Force

        # Check if Lenovo path exists, if not, create it
        if (-not (Test-Path -Path $lenovoPath -PathType Container))
        {
            Write-Output "Creating Think Bios Config Tool directory"
            New-Item -ItemType Directory -Path $lenovoPath -Force -ErrorAction Stop | Out-Null
        }

        # Change SVP using TBCT
        Write-Output "Changing Supervisor Password using Think Bios Config Tool"
        $msHtaPath = "$($env:SystemRoot)\System32\mshta.exe"
        Start-Process -FilePath $msHtaPath -ArgumentList "$htaFilePath $arguments" -Wait -NoNewWindow

        # Grab status from log file to determine if a reboot is required
        $logFile = (Get-ChildItem -Path $lenovoPath -Filter "*.txt").FullName
        if ($logFile)
        {
            # Read the content of the log file
            $logContent = Get-Content -Path $logFile

            # Check for "Success" in the log content
            if ($logContent | Select-String -Pattern "Success")
            {
                Write-Output "Supervisor Password changed successfully"
                # Write a status file for Intune detection
                Set-Content -Path $statusFilePath -Value "SVP changed" -Force
                # Flag to tell Intune a Soft Reboot is needed in order to update the SVP
                exit 3010
            }
            else
            {
                # Cannot set an initial SVP
                exit 1
            }
        }
    }
    else
    {
        # ThinkBiosConfig.hta or password file not found.
        exit 1
    }
}
catch
{
    Write-Error "An error occurred: $_"
    exit 1
}
