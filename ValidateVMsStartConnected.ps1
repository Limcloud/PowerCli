 # Requires VMware PowerCLI

$vCenter = "vc-01c.corp.internal"
$username = "administrator@vsphere.local"
$password = "VMware1!VMware1!"

$exportFolder = "C:\Temp"
$exportPath   = "$exportFolder\VM-NetworkAdapters-ConnectAtPowerOn.csv"

if (!(Test-Path $exportFolder)) {
    New-Item -ItemType Directory -Path $exportFolder | Out-Null
}

$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($username, $securePassword)

Connect-VIServer -Server $vCenter -Credential $credential

$results = @()

$vms = Get-VM

foreach ($vm in $vms) {
    $nics = Get-NetworkAdapter -VM $vm

    foreach ($nic in $nics) {
        $results += [PSCustomObject]@{
            VMName           = $vm.Name
            PowerState       = $vm.PowerState
            NetworkAdapter   = $nic.Name
            NetworkName      = $nic.NetworkName
            MacAddress       = $nic.MacAddress
            Connected        = $nic.ConnectionState.Connected
            StartConnected   = $nic.ConnectionState.StartConnected
            ConnectAtPowerOn = if ($nic.ConnectionState.StartConnected) { "Yes" } else { "No" }
        }
    }
}

$results | Format-Table -AutoSize

$results | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8 -Force

Write-Host "Reporte generado en: $exportPath" -ForegroundColor Green

Disconnect-VIServer -Server $vCenter -Confirm:$false 
