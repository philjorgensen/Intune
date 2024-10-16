 <#
    .SYNOPSIS
    Intel Processor Power Management detection script
    
    .DESCRIPTION
    This detection script is intended for an Intune Win32 app detection method.

    .NOTES
    There are 3 unique packages that support 3 different sets of models. Reference
    the ReadMe for more information.

#>

# Define array of versions to check (package IDs are for reference only)
$packageVersions = @(
    "1001.20240717", # nz9pm02w (https://download.lenovo.com/pccbbs/mobiles/nz9pm02w.html)
    "1003.20240717", # nzapm02w (https://download.lenovo.com/pccbbs/mobiles/nzapm02w.html)
    "1004.20240305"  # nzbpm02w (https://download.lenovo.com/pccbbs/mobiles/nzbpm02w.html)
)

# Suppress the success message by capturing and discarding it
$provisioningPackages = Get-ProvisioningPackage -AllInstalledPackages

foreach ($package in $provisioningPackages)
{
    $installedVersion = $package.Version

    if ($packageVersions -contains $installedVersion)
    {
        Write-Output("Package version $installedVersion is installed."); Exit 0
    }
    else
    {
        Write-Output("Package version $installedVersion is not installed."); Exit 1
    }
}