# URL to WinAIA Utility
$url = "https://download.lenovo.com/pccbbs/mobiles/giaw03ww.exe"
$destPath = Join-Path -Path (Join-Path -Path $env:ProgramData -ChildPath Lenovo) -ChildPath WinAIA
$destFile = $url.Split('/')[-1]

# Set owner variables
$ownerName = "Lenovo"
$ownerDept = "Commercial Deployment Readiness Team"
$ownerLocation = "Durham,NC"
$assetPrefix = "CDRT"

try {
    
    # Create directory for utility
    if (!(Test-Path -Path $destPath)) {
        New-Item -Path $destPath -ItemType Directory
    }

    # Download utility via HTTPS
    if (!(Get-ChildItem -Path "$destPath\$destFile" -ErrorAction SilentlyContinue)) {
        Start-BitsTransfer -Source $url -Destination "$destPath\$destFile"
    }

    # Extract contents
    $extract = "/VERYSILENT /DIR=$destPath /EXTRACT=YES"
    if (!(Get-ChildItem -Path $destPath -Filter WinAIA*)) {
        Start-Process -FilePath "$destPath\$destFile" -ArgumentList $extract -Wait
    }

    # Variable for last 5 numbers of Unique ID
    $uuid = (Get-CimInstance -Namespace root/CIMV2 -ClassName Win32_ComputerSystemProduct).UUID.Split("-")[4].Substring(6)

    <# 
        Set Owner Data with WinAIA Utility. 
        These are sample values and can be changed.
    #>
    Set-Location -Path $destPath
    .\WinAIA64.exe -silent -set "OWNERDATA.OWNERNAME=$ownerName"
    .\WinAIA64.exe -silent -set "OWNERDATA.DEPARTMENT=$ownerDept"
    .\WinAIA64.exe -silent -set "OWNERDATA.LOCATION=$ownerLocation"

    <#  
        Set Asset Number. Available through WMI by querying the SMBIOSASSetTag field of the Win32_SystemEnclosure class
        Example shows the $uuid is prefixed with CDRT. This can be replaced as you see fit.
    #>
    .\WinAIA64.exe -silent -set "USERASSETDATA.ASSET_NUMBER=$assetPrefix-$uuid"

    # AIA Output file
    .\WinAIA64.exe -silent -output-file "$destPath\WinAIA.log" -get OWNERDATA USERASSETDATA

    # Remove Package
    Remove-Item -LiteralPath "$destPath\$destFile" -Force

    Write-Output "Asset Tag Set"; Exit 0
    
}
catch {
    Write-Output $_.Exception.Message; Exit 1
}