 <#
    .SYNOPSIS
    Installs the Intel Processor Power Management package
    
    .DESCRIPTION
    This package installs the provisioning package (Intel PPM package) to tune power mode settings
    across AC/DC (Best Power Efficiency, Balanced, Best Performance).

    .NOTES
    There are 3 unique packages that support 3 different sets of models. Each region has a link to the
    ReadMe for its respective package.

#>

# Get the system machine type model
$systemMtm = ((Get-CimInstance -Namespace root/CIMV2 -ClassName Win32_ComputerSystem).Model.Substring(0, 4)).Trim()

# Get the directory where the script is running
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

# Define model arrays for each package
#region nz9pm02w
# https://download.lenovo.com/pccbbs/mobiles/nz9pm02w.html
$models_nz9pm02w = @(
    "21B3", "21B4", "21B5", "21B6", "21C1", "21C2", "21C3", "21C4", "21DC", "21DD",
    "21AK", "21AL", "21D8", "21D9", "21D6", "21D7", "21BT", "21BU", "21AH", "21AJ",
    "21BR", "21BS", "21DA", "21DB", "21BV", "21BW", "21CB", "21CC", "21DE", "21DF",
    "21ES", "21ET", "21E8", "21E9", "21CD", "21CE", "21BN", "21BQ", "21AW", "21AX"
)
#endregion

#region nzapm02w
# https://download.lenovo.com/pccbbs/mobiles/nzapm02w.html
$models_nzapm02w = @(
    "21JK", "21JL", "21JN", "21JQ", "21FG", "21FH", "21FJ", "21FK", "21H3", "21H4",
    "21FV", "21FW", "21HF", "21HG", "21FA", "21FB", "21HK", "21HL", "21FC", "21FD",
    "21HD", "21HE", "21F6", "21F7", "21HH", "21HJ", "21BV", "21BW", "21HM", "21HN",
    "21K1", "21K2", "21HQ", "21HR", "21EX", "21EY", "21F2", "21F3"
)
#endregion

#region nzbpm02w
# https://download.lenovo.com/pccbbs/mobiles/nzbpm02w.html
$models_nzbpm02w = @(
    "21M7", "21M8", "21MA", "21MB", "21LM", "21LN", "21LB", "21LC", "21L1", "21L2",
    "21L3", "21L4", "21KV", "21KW", "21G2", "21G3", "21KS", "21KT", "21KX", "21KY",
    "21ML", "21MM", "21LS", "21LT", "21MN", "21MQ", "21KE", "21KF", "21KC", "21KD",
    "21LK", "21LL", "21LW", "21LX", "21LU", "21LV"
)
#endregion

# Create a hashtable to map package IDs to model arrays
$packageModels = @{
    "nz9pm02w" = $models_nz9pm02w
    "nzapm02w" = $models_nzapm02w
    "nzbpm02w" = $models_nzbpm02w
}

# Create a hashtable to map package IDs to executable paths
$packageExecutables = @{
    "nz9pm02w" = Join-Path -Path $scriptDirectory -ChildPath "nz9pm02w.exe"
    "nzapm02w" = Join-Path -Path $scriptDirectory -ChildPath "nzapm02w.exe"
    "nzbpm02w" = Join-Path -Path $scriptDirectory -ChildPath "nzbpm02w.exe"
}

# Initialize a flag to track if a match is found
$matchFound = $false

# Iterate through each package and check for a match
foreach ($packageId in $packageModels.Keys)
{
    $models = $packageModels[$packageId]
    # Check if the system model matches any pattern in the current package
    foreach ($model in $models)
    {
        if ($systemMtm -like "$model*")
        {
            Write-Output("This system matches package $packageId.")
            $matchFound = $true
            # Install the corresponding executable
            $executablePath = $packageExecutables[$packageId]
            $executableParam = "/verysilent"
            if (Test-Path -Path $executablePath)
            {
                Write-Output("Installing the Intel Processor Power Management package...")
                # Start the process and wait for it to finish
                $process = Start-Process -FilePath $executablePath -ArgumentList $executableParam -Wait -PassThru
                # Capture the exit code (return code)
                $exitCode = $process.ExitCode
                # Handle the return codes
                switch ($exitCode)
                {
                    0 { Write-Output("Installation SUCCESS; System restart is required."); return 0 }
                    1 { Write-Output("Installation FAIL."); return 1 }
                    2 { Write-Output("Equal PPM package is already installed."); return 2 }
                    default { Write-Output("Unknown return code: $exitCode") }
                }
            }
            else
            {
                Write-Output("Executable not found for package $packageId.")
            }
            break  # Exit after finding the first match
        }
    }
}

# If no match is found, output a message
if (-not $matchFound)
{
    Write-Output("No match found for system model $systemMtm.")
}
