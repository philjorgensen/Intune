try {
    Install-WinGetPackage -Id Lenovo.ThinInstaller -Confirm:$false; Exit 0
}
catch {
    Write-Warning -Message $_.Exception.Message; Exit 1
}