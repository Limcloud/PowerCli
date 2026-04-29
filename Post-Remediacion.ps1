# ==========================================
# Post-Remediation Secure Boot PK Update
# ==========================================

$vCenter = "vc-l-01a.corp.internal"
$DiskPath = "[ds-nfs-01] PKmedia.vmdk"
$SnapshotName = "Before-PK-Update"

function Show-Step {
    param($Text,$Color="Cyan")
    Write-Host $Text -ForegroundColor $Color
}

if (-not $global:DefaultVIServer) {
    Show-Step "Conectando a vCenter $vCenter ..."
    Connect-VIServer $vCenter | Out-Null
    Show-Step "Conectado a vCenter." "Green"
}

$vmName = (Read-Host "Nombre de la VM").Trim()
$vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue

if (!$vm) {
    Show-Step "VM no encontrada." "Red"
    return
}

Show-Step "`nPost proceso para VM: $vmName" "Yellow"

# -------------------------------------------------
# Apagar VM
# -------------------------------------------------
if ($vm.PowerState -eq "PoweredOn") {

    Show-Step "Solicitando apagado guest OS..." "Cyan"
    Shutdown-VMGuest -VM $vm -Confirm:$false -ErrorAction SilentlyContinue

    do {
        Start-Sleep 20
        $vm = Get-VM -Name $vmName

        if ($vm.PowerState -eq "PoweredOff") {
            Show-Step "VM apagada correctamente." "Green"
        }
        else {
            Show-Step "Esperando apagado... estado actual: $($vm.PowerState)" "Yellow"
        }

    } until ($vm.PowerState -eq "PoweredOff")

}
else {
    Show-Step "La VM ya estaba apagada." "Gray"
}

# -------------------------------------------------
# Remover disco PK
# -------------------------------------------------
Show-Step "Buscando disco PK adjunto..." "Cyan"

$disk = Get-HardDisk -VM $vm | Where-Object {
    $_.Filename -like "*PKmedia.vmdk*"
}

if ($disk) {
    $disk | ForEach-Object {
        Show-Step "Removiendo disco: $($_.Filename)" "Cyan"
        Remove-HardDisk -HardDisk $_ -DeletePermanently:$false -Confirm:$false
    }

    Show-Step "Disco PK removido de la VM." "Green"
}
else {
    Show-Step "No se encontró disco PK adjunto." "Yellow"
}

# -------------------------------------------------
# Remover advanced setting
# -------------------------------------------------
Show-Step "Removiendo uefi.allowAuthBypass..." "Cyan"

$setting = Get-AdvancedSetting -Entity $vm `
    -Name "uefi.allowAuthBypass" `
    -ErrorAction SilentlyContinue

if ($setting) {
    Remove-AdvancedSetting $setting -Confirm:$false
    Show-Step "Advanced setting removido." "Green"
}
else {
    Show-Step "Advanced setting no existía." "Yellow"
}

# -------------------------------------------------
# Desactivar Force EFI Setup
# -------------------------------------------------
Show-Step "Desactivando Force EFI Setup..." "Cyan"

$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.BootOptions = New-Object VMware.Vim.VirtualMachineBootOptions
$spec.BootOptions.EnterBIOSSetup = $false

(Get-View $vm.Id).ReconfigVM_Task($spec) | Out-Null

Show-Step "Force EFI Setup deshabilitado." "Green"

# -------------------------------------------------
# Snapshot - preguntar
# -------------------------------------------------
$snap = Get-Snapshot -VM $vm -Name $SnapshotName -ErrorAction SilentlyContinue

if ($snap) {

    $resp = Read-Host "Desea remover el snapshot '$SnapshotName'? (S/N)"

    if ($resp.ToUpper() -eq "S") {

        Show-Step "Removiendo snapshot..." "Cyan"
        Remove-Snapshot -Snapshot $snap -Confirm:$false
        Show-Step "Snapshot removido." "Green"

    }
    else {
        Show-Step "Snapshot conservado." "Yellow"
    }
}
else {
    Show-Step "No se encontró snapshot $SnapshotName." "Gray"
}

# -------------------------------------------------
# Encender VM
# -------------------------------------------------
Show-Step "Encendiendo VM..." "Cyan"
Start-VM $vm | Out-Null
Show-Step "VM encendida." "Green"

# -------------------------------------------------
# Final
# -------------------------------------------------
Write-Host ""
Show-Step "Proceso post-remediación completado." "Green"
Show-Step "Recomendado: validar PK dentro del guest." "White"
Show-Step '$pk = Get-SecureBootUEFI -Name PK' "Gray"