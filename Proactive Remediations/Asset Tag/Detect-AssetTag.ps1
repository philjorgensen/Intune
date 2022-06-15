$AssetTag = (Get-CimInstance -Namespace root/CIMV2 -ClassName Win32_SystemEnclosure).SMBIOSAssetTag
$Model = (Get-CimInstance -Namespace root/CIMV2 -ClassName Win32_ComputerSystemProduct).Version

if ($Model -notmatch "ThinkPad") {
    Write-Output "Device not supported"; Exit 0
}

if ($AssetTag -match "No Asset") {
    Write-Output "Asset Tag not set"; Exit 1
}
else {
    Write-Output "Asset Tag already set"; Exit 0
}