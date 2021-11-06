<# 
DISCLAIMER: 

These sample scripts are not supported under any Lenovo standard support   

program or service. The sample scripts are provided AS IS without warranty   

of any kind. Lenovo further disclaims all implied warranties including,   

without limitation, any implied warranties of merchantability or of fitness for   

a particular purpose. The entire risk arising out of the use or performance of   

the sample scripts and documentation remains with you. In no event shall   

Lenovo, its authors, or anyone else involved in the creation, production, or   

delivery of the scripts be liable for any damages whatsoever (including,   

without limitation, damages for loss of business profits, business interruption,   

loss of business information, or other pecuniary loss) arising out of the use   

of or inability to use the sample scripts or documentation, even if Lenovo   

has been advised of the possibility of such damages.  
#> 

<#
.SYNOPSIS
    Script to install and configure Lenovo System Update. 

.DESCRIPTION
    Script will install Lenovo System Update and set the necessary registry subkeys and values that downloads/installs 
    reboot type 3 packages on the system.  Certain UI settings are configured for an optimal end user experience.
    The default Scheduled Task created by System Update will be disabled.  A custom Scheduled Task for System Update will be created.
    
.NOTES
    FileName: Invoke-SystemUpdate.ps1
    Author: Philip Jorgensen

    Update the $pkg variable with the version you plan on installing
#>

##### Install System Update
$pkg = "system_update_5.07.0110"
$switches = "/verysilent /norestart"
Start-Process ".\$pkg" -ArgumentList $switches -Wait

##### Set SU AdminCommandLine
$RegKey = "HKLM:\SOFTWARE\Policies\Lenovo\System Update\UserSettings\General"
$RegName = "AdminCommandLine"
$RegValue = "/CM -search A -action INSTALL -includerebootpackages 3 -noicon -noreboot -exporttowmi"

# Create Subkeys if they don't exist
if (!(Test-Path $RegKey)) {
    New-Item -Path $RegKey -Force | Out-Null
    New-ItemProperty -Path $RegKey -Name $RegName -Value $RegValue | Out-Null
}
else {
    New-ItemProperty -Path $RegKey -Name $RegName -Value $RegValue -Force | Out-Null
}

##### Configure SU interface
$ui = "HKLM:\SOFTWARE\WOW6432Node\Lenovo\System Update\Preferences\UserSettings\General"
$values = @{

    "AskBeforeClosing"     = "NO"

    "DisplayLicenseNotice" = "NO"

    "MetricsEnabled"       = "NO"
                             
    "DebugEnable"          = "YES"

}

if (Test-Path $ui) {
    foreach ($item in $values.GetEnumerator() ) {
        New-ItemProperty -Path $ui -Name $item.Key -Value $item.Value -Force
    }
}

<# 
Run SU and wait until the Tvsukernel process finishes.
Once the Tvsukernel ends, AutoPilot flow will continue.
#>
$su = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath "Lenovo\System Update\tvsu.exe"
&$su /CM | Out-Null
Wait-Process -Name Tvsukernel

# Disable the default System Update scheduled tasks
Get-ScheduledTask -TaskPath "\TVT\" | Disable-ScheduledTask

##### Disable Scheduler Ability.  
# This will prevent System Update from creating the default scheduled tasks when updating to future releases.
$sa = "HKLM:\SOFTWARE\WOW6432Node\Lenovo\System Update\Preferences\UserSettings\Scheduler"
Set-ItemProperty -Path $sa -Name "SchedulerAbility" -Value "NO"

##### Create a custom scheduled task for System Update
$taskAction = New-ScheduledTaskAction -Execute $su -Argument '/CM'
$taskTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 9am
$taskUserPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM'
$taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8
$task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Trigger $taskTrigger -Settings $taskSettings
Register-ScheduledTask -TaskName 'Run-TVSU' -InputObject $task -Force