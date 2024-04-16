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
    reboot type 3 packages on the system. Certain UI settings are configured for an optimal end user experience.
    The default scheduled task created by System Update will be disabled. A custom scheduled task for System Update will be created.
    
.NOTES
    FileName: Invoke-SystemUpdate.ps1
    Author: Philip Jorgensen

    Created:    2023-10-10
    Change:     2024-04-15
                    Switch to winget installation method using PowerShell 7 and the Microsoft.Winget.Client module
                    Add logging
                    Add soft reboot code to finish driver installation for drivers that may require it
#>

$LogPath = Join-Path -Path (Join-Path -Path $env:ProgramData -ChildPath "Lenovo") -ChildPath "SystemUpdate"
Start-Transcript -Path $LogPath\Autopilot-SystemUpdate.log

<# 
    Credit to Andrew Taylor
    https://github.com/andrew-s-taylor/public/blob/main/Powershell%20Scripts/Intune/deploy-winget-during-esp.ps1
#>
#GitHub API endpoint for PowerShell releases
$githubApiUrl = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'

#Fetch the latest release details
$release = Invoke-RestMethod -Uri $githubApiUrl

#Find asset with .msi in the name
$asset = $release.assets | Where-Object { $_.name -like "*msi*" -and $_.name -like "*x64*" }

#Get the download URL and filename of the asset (assuming it's a MSI file)
$downloadUrl = $asset.browser_download_url
$filename = $asset.name

#Download the latest release
Invoke-WebRequest -Uri $downloadUrl -OutFile $filename

#Install PowerShell 7
Start-Process msiexec.exe -Wait -ArgumentList "/I $filename /qn"

#Start a new PowerShell 7 session
$pwshExecutable = "C:\Program Files\PowerShell\7\pwsh.exe"

#Run a script block in PowerShell 7
& $pwshExecutable -Command {
    $provider = Get-PackageProvider -Name NuGet -ErrorAction Ignore
    if (-not($provider))
    {
        Write-Host "Installing provider NuGet"
        Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies
    }
}
& $pwshExecutable -Command {
    Install-Module -Name Microsoft.Winget.Client -Force -AllowClobber
}
& $pwshExecutable -Command {
    Import-Module -Name Microsoft.Winget.Client
}
& $pwshExecutable -Command {
    Repair-WinGetPackageManager
}
& $pwshExecutable -Command {
    Install-WinGetPackage -Id Lenovo.SystemUpdate
}

#Set SU AdminCommandLine
$Key = "HKLM:\SOFTWARE\Policies\Lenovo\System Update\UserSettings\General"
$Name = "AdminCommandLine"
$Value = "/CM -search A -action INSTALL -includerebootpackages 3 -noicon -noreboot -exporttowmi"

#Create subkeys if they don't exist
if (-not(Test-Path -Path $Key))
{
    New-Item -Path $Key -Force | Out-Null
    New-ItemProperty -Path $Key -Name $Name -Value $Value | Out-Null
}
else
{
    New-ItemProperty -Path $Key -Name $Name -Value $Value -Force | Out-Null
}
Write-Host "AdminCommandLine value set"

#Configure System Update interface
$Key2 = "HKLM:\SOFTWARE\WOW6432Node\Lenovo\System Update\Preferences\UserSettings\General"
$Values = @{

    "AskBeforeClosing"     = "NO"

    "DisplayLicenseNotice" = "NO"

    "MetricsEnabled"       = "NO"
                             
    "DebugEnable"          = "YES"
}

if (Test-Path -Path $Key2)
{
    foreach ($Value in $Values.GetEnumerator() )
    {
        New-ItemProperty -Path $Key2 -Name $Value.Key -Value $Value.Value -Force
    }
}
Write-Host "System Update GUI configured"

<# 
Run SU and wait until the Tvsukernel process finishes.
Once the Tvsukernel process ends, Autopilot flow will continue.
#>
$systemUpdate = "$(${env:ProgramFiles(x86)})\Lenovo\System Update\tvsu.exe"
& $systemUpdate /CM

Write-Host "Execute System Update and search for drivers"

#Wait for tvsukernel to initialize
Start-Sleep -Seconds 15
Wait-Process -Name Tvsukernel
Write-Host "Drivers installed"

#Disable the default System Update scheduled tasks
Get-ScheduledTask -TaskPath "\TVT\" | Disable-ScheduledTask
Write-Host "Default scheduled tasks disabled"

<# 
Disable Scheduler Ability.  
This will prevent System Update from creating the default scheduled tasks when updating to future releases.
#> 
$schdAbility = "HKLM:\SOFTWARE\WOW6432Node\Lenovo\System Update\Preferences\UserSettings\Scheduler"
Set-ItemProperty -Path $schdAbility -Name "SchedulerAbility" -Value "NO"

#Create a custom scheduled task for System Update
$taskActionParams = @{
    Execute  = $systemUpdate
    Argument = '/CM'
}
$taskAction = New-ScheduledTaskAction @taskActionParams

#Adjust to your requirements
$taskTriggerParams = @{
    Weekly     = $true
    DaysOfWeek = 'Monday'
    At         = "9am"
}
$taskTrigger = New-ScheduledTaskTrigger @taskTriggerParams
$taskUserPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM'
$taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8

$newTaskParams = @{
    TaskPath    = "\TVT\"
    TaskName    = "Custom-RunTVSU"
    Description = "System Update searches and installs new drivers only"
    Action      = $taskAction
    Principal   = $taskUserPrincipal
    Trigger     = $taskTrigger
    Settings    = $taskSettings
}
Register-ScheduledTask @newTaskParams -Force | Out-Null
Write-Host "Custom scheduled task created"
Write-Host "Exiting with a 3010 return code for a soft reboot to complete driver installation."
Stop-Transcript
Exit 3010