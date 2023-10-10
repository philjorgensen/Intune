$username = "defaultuser0"
$currentuser = (Get-Process -IncludeUserName -Name explorer | Select-Object -ExpandProperty UserName).Split('\')[1]

if ($currentuser -eq $username)
{     
    return $true
    Exit 0
}
else
{
    Exit 1
}