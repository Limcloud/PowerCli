# =========================
# vCenter 9 conexión
# =========================

$vc9 = "vc-01c.corp.internal"
$user = "administrator@vsphere.local"
$pass = "VMware1!VMware1!"

$sec = ConvertTo-SecureString $pass -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($user, $sec)

Connect-VIServer -Server $vc9 -Credential $cred

$inFile = ".\roles-exportados-vc8.json"

$roles = Get-Content $inFile -Raw | ConvertFrom-Json

# Cache de privileges válidos en destino
$validPriv = Get-VIPrivilege | Select-Object -ExpandProperty Id

foreach ($r in $roles) {

    # Verificar si el rol ya existe
    if (Get-VIRole -Name $r.Name -ErrorAction SilentlyContinue) {
        Write-Host "SKIP — ya existe:" $r.Name -ForegroundColor Yellow
        continue
    }

    # Filtrar privileges válidos
    $filtered = @($r.Privileges | Where-Object { $_ -in $validPriv })

    if ($filtered.Count -eq 0) {
        Write-Warning "SKIP — sin privileges válidos: $($r.Name)"
        continue
    }

    # Crear rol
    New-VIRole -Name $r.Name -Privilege (Get-VIPrivilege -Id $filtered) | Out-Null
    Write-Host "CREADO:" $r.Name -ForegroundColor Green

    # Log de privileges faltantes
    $missing = @($r.Privileges | Where-Object { $_ -notin $validPriv })
    if ($missing.Count -gt 0) {
        Write-Warning "  -> $($missing.Count) privileges no existen en vCenter 9"
    }
}

Disconnect-VIServer $vc9 -Confirm:$false
