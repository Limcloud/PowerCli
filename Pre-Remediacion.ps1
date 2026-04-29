# ==========================================
# Pre-Remediation Secure Boot PK Update
# ==========================================

$vCenter = "vc-l-01a.corp.internal"
$DiskPath = "[DS-BCCR-Lab-NFS-01] PKmedia.vmdk"
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

$vmName = Read-Host "Nombre de la VM"
$vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue

if (!$vm) {
    Show-Step "VM no encontrada." "Red"
    return
}

Show-Step "`nPreparando VM: $vmName" "Yellow"

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
# Snapshot sin memoria
# -------------------------------------------------
Show-Step "Creando snapshot: $SnapshotName ..." "Cyan"

New-Snapshot `
    -VM $vm `
    -Name $SnapshotName `
    -Description "Before PK remediation" `
    -Memory:$false `
    -Quiesce:$false | Out-Null

Show-Step "Snapshot creado correctamente." "Green"

# -------------------------------------------------
# Adjuntar disco PK
# -------------------------------------------------
Show-Step "Adjuntando disco PK: $DiskPath" "Cyan"

New-HardDisk -VM $vm -DiskPath $DiskPath | Out-Null

Show-Step "Disco PK adjuntado." "Green"

# -------------------------------------------------
# Advanced Setting
# -------------------------------------------------
Show-Step "Agregando advanced setting uefi.allowAuthBypass=TRUE" "Cyan"

New-AdvancedSetting `
    -Entity $vm `
    -Name "uefi.allowAuthBypass" `
    -Value "TRUE" `
    -Force -Confirm:$false | Out-Null

Show-Step "Advanced setting aplicado." "Green"

# -------------------------------------------------
# Force EFI Setup
# -------------------------------------------------
Show-Step "Activando Force EFI Setup..." "Cyan"

$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.BootOptions = New-Object VMware.Vim.VirtualMachineBootOptions
$spec.BootOptions.EnterBIOSSetup = $true

(Get-View $vm.Id).ReconfigVM_Task($spec) | Out-Null

Show-Step "Force EFI Setup habilitado." "Green"

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
Show-Step "VM lista para paso manual en UEFI:" "Green"
Show-Step "Secure Boot Configuration > PK Options > Enroll PK" "White"