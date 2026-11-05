<#
    .SYNOPSIS
    Win32 app requirement rule: returns $true once OOBE is complete.

    .DESCRIPTION
    Calls kernel32!OOBEComplete. Configure the requirement rule with a Boolean return type,
    Operator Equals, Value No, so the app only installs while the device is in OOBE
    (e.g. Autopilot pre-provisioning).

    .NOTES
    Adapted from https://oofhours.com/2023/09/15/detecting-when-you-are-in-oobe/
#>

$Definition = @"

using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Api
{
    public class Kernel32
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern int OOBEComplete(ref int bIsOOBEComplete);
    }
}
"@

Add-Type -TypeDefinition $Definition -Language CSharp

$IsOOBEComplete = $false
$null = [Api.Kernel32]::OOBEComplete([ref] $IsOOBEComplete)

if ($IsOOBEComplete -eq '1') { return $true }
else { return $false }
