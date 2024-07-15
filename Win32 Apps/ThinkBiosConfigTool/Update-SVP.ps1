# Define variables
$lenovoPath = Join-Path -Path $env:ProgramData -ChildPath "Lenovo\ThinkBiosConfig"
$htaFilePath = Join-Path -Path $PSScriptRoot -ChildPath "ThinkBiosConfig.hta"
$passFilePath = (Get-ChildItem -Path $PSScriptRoot -Filter "*.ini").FullName
$secretKey = ""
$arguments = "`"file=$passFilePath`" `"pass=$secretKey`" `"log=$lenovoPath`""
$statusFilePath = Join-Path -Path $lenovoPath -ChildPath "svp.status"

try {
    # Check if ThinkBiosConfig.hta and password file exist
    $htaExists = Test-Path -Path $htaFilePath -PathType Leaf
    $passFileExists = Test-Path -Path $passFilePath -PathType Leaf

    if ($htaExists -and $passFileExists) {
        # Remove previous log file if it exists
        Get-ChildItem -Path $lenovoPath -Filter "*.txt" -ErrorAction SilentlyContinue | Remove-Item -Force

        # Check if Lenovo path exists, if not, create it
        if (-not (Test-Path -Path $lenovoPath -PathType Container)) {
            Write-Output "Creating Think Bios Config Tool directory"
            New-Item -ItemType Directory -Path $lenovoPath -Force -ErrorAction Stop | Out-Null
        }

        # Change SVP using TBCT
        Write-Output "Changing Supervisor Password using Think Bios Config Tool"
        Start-Process -FilePath $env:SystemRoot\system32\cmd.exe -ArgumentList "/c $htaFilePath $arguments" -Wait -NoNewWindow

        # Grab status from log file to determine if a reboot is required
        $logFile = (Get-ChildItem -Path $lenovoPath -Filter "*.txt").FullName
        if ($logFile) {
            # Read the content of the log file
            $logContent = Get-Content -Path $logFile

            # Check for "Success" in the log content
            if ($logContent | Select-String -Pattern "Success") {
                Write-Output "Supervisor Password changed successfully"
                # Write a status file for Intune detection
                Set-Content -Path $statusFilePath -Value "SVP changed" -Force
                # Flag to tell Intune a Soft Reboot is needed in order to update the SVP
                Exit 3010
            } else {
                # Cannot set an initial SVP
                Exit 1
            }
        }
    } else {
        # ThinkBiosConfig.hta or password file not found.
        Exit 1
    }
} catch {
    Write-Error "An error occurred: $_"
    Exit 1
}
