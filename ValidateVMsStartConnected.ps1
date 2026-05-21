# Requires VMware PowerCLI
# Install-Module VMware.PowerCLI -Scope CurrentUser

$vCenter = "vcsa-p-01.vspotcr.com"
$username = "administrator@vsphere.local"
$password = "VMware1!"

# Convertir password a SecureString
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force

# Crear credencial
$credential = New-Object System.Management.Automation.PSCredential ($username, $securePassword)

# Conectarse al vCenter
Connect-VIServer -Server $vCenter -Credential $credential

# Obtener información de VMs y NICs
$results = Get-VM | ForEach-Object {
    $vm = $_

    Get-NetworkAdapter -VM $vm | ForEach-Object {
        [PSCustomObject]@{
            VMName           = $vm.Name
            PowerState       = $vm.PowerState
            NetworkAdapter   = $_.Name
            NetworkName      = $_.NetworkName
            MacAddress       = $_.MacAddress
            Connected        = $_.ConnectionState.Connected
            StartConnected   = $_.ConnectionState.StartConnected
            ConnectAtPowerOn = if ($_.ConnectionState.StartConnected) { "Yes" } else { "No" }
        }
    }
}

# Mostrar resultados
$results | Format-Table -AutoSize

# Export opcional
$results | Export-Csv -Path ".\VM-NetworkAdapters-ConnectAtPowerOn.csv" -NoTypeInformation -Encoding UTF8

# Desconectarse
Disconnect-VIServer -Server $vCenter -Confirm:$false
