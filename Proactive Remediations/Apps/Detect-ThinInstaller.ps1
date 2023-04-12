# Enable Tls 1.2 support to download modules
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

if (-not(Get-InstalledModule -Name PSWinGet -ErrorAction SilentlyContinue)) {
    Write-Output -InputObject "`nPSWinGet module was not found. Installing ..."
    try {
        # Install NuGet package provider
        Install-PackageProvider -Name "NuGet" -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop
        # Install PSWinGet module for easier app version comparisons
        Install-Module PSWinGet -Scope AllUsers -Force -Confirm:$false
    }
    catch {
        Write-Error -Message $_.Exception.Message
    }
}

$ThinInstallerPath = Join-Path -Path (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath Lenovo) -ChildPath "ThinInstaller"
if (-not(Test-Path -Path $ThinInstallerPath)) {
    Write-Output -InputObject "Thin Installer not present..."; Exit 1
} else {
    Write-Output -InputObject "Checking the Winget repository for an updated version..."
}

[version]$LocalVersion = $(try { ((Get-ChildItem -Path $ThinInstallerPath -Filter "thininstaller.exe" -Recurse).VersionInfo.FileVersion) } catch { $null })
[version]$WingetVersion = (Find-WinGetPackage -Id Lenovo.ThinInstaller).Version
if ($LocalVersion -lt $WingetVersion) {
    Write-Output -InputObject "Thin Installer is not current..."; Exit 1
}
else {
    Write-Output -InputObject "Thin Installer is current..."; Exit 0
}