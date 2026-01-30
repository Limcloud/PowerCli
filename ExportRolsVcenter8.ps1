$vc8 = "vc-l-01a.corp.internal"
$user = "administrator@vsphere.local"
$pass = "VMware1!"

$sec = ConvertTo-SecureString $pass -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($user, $sec)

Connect-VIServer -Server $vc8 -Credential $cred
# Exporta todos los roles que No son de sistema

$outFile = ".\roles-exportados-vc8.json"

$roles = Get-VIRole | Where-Object { $_.IsSystem -eq $false } | ForEach-Object {
    [PSCustomObject]@{
        Name       = $_.Name
        Privileges = (Get-VIPrivilege -Role $_ | Select-Object -ExpandProperty Id)
    }
}

$roles | ConvertTo-Json -Depth 10 | Out-File -Encoding UTF8 $outFile

Write-Host "Export listo -> $outFile" -ForegroundColor Green
Write-Host "Cantidad de roles exportados:" $roles.Count -ForegroundColor Cyan
Disconnect-VIServer $vc8 -Confirm:$false
