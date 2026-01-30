# =========================
# vCenter 8 conexión
# =========================

$vc8 = "vc-l-01a.corp.internal"
$user = "administrator@vsphere.local"
$pass = "VMware1!"

$sec = ConvertTo-SecureString $pass -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($user, $sec)

Connect-VIServer -Server $vc8 -Credential $cred


# =========================
# Función para crear nuevos roles en vCenter
# =========================

function New-LabRoleIfMissing {
  param(
    [string]$RoleName,
    [string[]]$PrivilegeIds
  )

  if (Get-VIRole -Name $RoleName -ErrorAction SilentlyContinue) {
    Write-Host "Ya existe:" $RoleName -ForegroundColor Yellow
    return
  }

  $privObjs = Get-VIPrivilege -Id $PrivilegeIds -ErrorAction SilentlyContinue
  New-VIRole -Name $RoleName -Privilege $privObjs | Out-Null

  Write-Host "Creado:" $RoleName -ForegroundColor Green
}


# =========================
# Crear 5 roles de lab
# =========================

# Rol 1
New-LabRoleIfMissing "Lab-VM-Operator" @(
"VirtualMachine.Interact.PowerOn",
"VirtualMachine.Interact.PowerOff",
"VirtualMachine.Interact.Reset",
"VirtualMachine.Interact.Suspend",
"VirtualMachine.Interact.ConsoleInteract"
)

# Rol 2
New-LabRoleIfMissing "Lab-VM-ViewerPlus" @(
"System.View",
"VirtualMachine.Inventory.Read",
"VirtualMachine.Interact.ConsoleInteract"
)

# Rol 3
New-LabRoleIfMissing "Lab-Snapshot-Operator" @(
"VirtualMachine.State.CreateSnapshot",
"VirtualMachine.State.RemoveSnapshot",
"VirtualMachine.State.RevertToSnapshot"
)

# Rol 4
New-LabRoleIfMissing "Lab-Datastore-Consumer" @(
"Datastore.Browse",
"Datastore.FileManagement"
)

# Rol 5
New-LabRoleIfMissing "Lab-Network-Consumer" @(
"Network.Assign",
"Network.Config"
)


# =========================
# Validación
# =========================

Get-VIRole | Where {$_.Name -like "Lab-*"} | Format-Table Name,IsSystem
Disconnect-VIServer $vc8 -Confirm:$false
