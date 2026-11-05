<#
    .SYNOPSIS
    Win32 app requirement rule: returns $true when a BIOS password is set.

    .DESCRIPTION
    Reads PasswordState from the Lenovo_BiosPasswordSettings WMI class. A value of 0 means no
    password is set. Configure the requirement rule with a Boolean return type, Operator Equals,
    Value Yes.
#>

$namespace = "root\wmi"
$class = "Lenovo_BiosPasswordSettings"
$value = (Get-CimInstance -Namespace $namespace -ClassName $class -ErrorAction SilentlyContinue).PasswordState

if ($value -ne 0) { return $true } # Password is set
else { return $false } # No password set
