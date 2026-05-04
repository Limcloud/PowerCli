 # =====================================================================
# Secure Boot VMware KB Assessment - Segun VMware KB 423893 y 423919
# =====================================================================

param(
    [string]$vCenter = "vc-l-01a.corp.internal",
    [string]$CsvPath = ".\vms.csv",
    [string]$OutputXlsx = ".\SecureBoot_Assessment.xlsx"
)

Import-Module ImportExcel

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

function Show-Line {
    param($Label,$Value,$Color="White")
    Write-Host ("  {0,-22} {1}" -f $Label,$Value) -ForegroundColor $Color
}

$vCenterCred = Get-Credential -Message "Credenciales vCenter"
$GuestCred   = Get-Credential -Message "Credenciales Windows Guest"

Connect-VIServer $vCenter -Credential $vCenterCred | Out-Null

$vmList = Import-Csv $CsvPath
$results = @()
$total = $vmList.Count
$i = 0

foreach ($row in $vmList) {

    $i++
    $vmName = $row.VMName.Trim()

    Write-Progress -Activity "Secure Boot Assessment" `
        -Status "$vmName ($i de $total)" `
        -PercentComplete (($i / $total) * 100)

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor DarkGray
    Write-Host "[$i/$total] $vmName" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor DarkGray

    $obj = [ordered]@{
        VMName       = $vmName
        Exists       = $false
        PowerOn      = $false
        EFI          = $false
        SecureBoot   = $false
        ToolsRunning = $false
        GuestAccess  = $false
        PK           = ""
        KEK2023      = ""
        DB2023       = ""
        Event1801    = ""
        Event1769    = ""
        Event1799    = ""
        Event1808    = ""
        Assessment   = ""
        Notes        = ""
    }

    $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue

    if (!$vm) {
        Show-Line "Exists" "No" "Red"
        Show-Line "RESULT" "Unknown" "Red"
        $obj.Assessment = "Unknown"
        $obj.Notes = "VM not found"
        $results += [pscustomobject]$obj
        continue
    }

    $obj.Exists = $true
    Show-Line "Exists" "Yes" "Green"

    $view = Get-View $vm.Id

    $obj.PowerOn      = ($vm.PowerState -eq "PoweredOn")
    $obj.EFI          = ($view.Config.Firmware -eq "efi")
    $obj.SecureBoot   = ($view.Config.BootOptions.EfiSecureBootEnabled -eq $true)
    $obj.ToolsRunning = ($view.Guest.ToolsRunningStatus -eq "guestToolsRunning")

    Show-Line "Power State" ($(if($obj.PowerOn){"ON"}else{"OFF"})) ($(if($obj.PowerOn){"Green"}else{"Red"}))
    Show-Line "Firmware" ($(if($obj.EFI){"EFI"}else{"BIOS"})) ($(if($obj.EFI){"Green"}else{"Yellow"}))
    Show-Line "Secure Boot" ($(if($obj.SecureBoot){"Enabled"}else{"Disabled"})) ($(if($obj.SecureBoot){"Green"}else{"Yellow"}))
    Show-Line "VMware Tools" ($(if($obj.ToolsRunning){"Running"}else{"Stopped"})) ($(if($obj.ToolsRunning){"Green"}else{"Yellow"}))

    if (!$obj.PowerOn) {
        $obj.Assessment = "Skipped"
        Show-Line "RESULT" "Skipped (Powered Off)" "Yellow"
        $results += [pscustomobject]$obj
        continue
    }

    if (!$obj.EFI -or !$obj.SecureBoot) {
        $obj.Assessment = "Not Applicable"
        Show-Line "RESULT" "Not Applicable" "Gray"
        $results += [pscustomobject]$obj
        continue
    }

    if (!$obj.ToolsRunning) {
        $obj.Assessment = "Unknown"
        Show-Line "RESULT" "Unknown (Tools not running)" "Yellow"
        $results += [pscustomobject]$obj
        continue
    }

    try {

$script = @'
try {
    $pk = Get-SecureBootUEFI -Name PK
    if ($pk.Bytes.Length -le 45) { $pkResult = "Invalid" } else { $pkResult = "OK" }
} catch { $pkResult = "Error" }

try {
    $kek = Get-SecureBootUEFI -Name KEK
    $txt = [System.Text.Encoding]::ASCII.GetString($kek.Bytes)
    if ($txt -match "KEK 2K CA 2023") { $kekResult = "Present" } else { $kekResult = "Missing" }
} catch { $kekResult = "Error" }

try {
    $db = Get-SecureBootUEFI -Name db
    $txt2 = [System.Text.Encoding]::ASCII.GetString($db.Bytes)
    if ($txt2 -match "Windows UEFI CA 2023") { $dbResult = "Present" } else { $dbResult = "Missing" }
} catch { $dbResult = "Error" }

# Eventos
function Get-Evt($id) {
    try {
        $e = Get-WinEvent -FilterHashtable @{LogName='System';Id=$id} -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($e) { "Yes" } else { "No" }
    } catch { "No" }
}

$evt1801 = Get-Evt 1801
$evt1769 = Get-Evt 1769
$evt1799 = Get-Evt 1799
$evt1808 = Get-Evt 1808

Write-Output "PK=$pkResult"
Write-Output "KEK=$kekResult"
Write-Output "DB=$dbResult"
Write-Output "EV1801=$evt1801"
Write-Output "EV1769=$evt1769"
Write-Output "EV1799=$evt1799"
Write-Output "EV1808=$evt1808"
'@

        $r = Invoke-VMScript -VM $vm -GuestCredential $GuestCred -ScriptType PowerShell -ScriptText $script -ErrorAction Stop

        $obj.GuestAccess = $true
        Show-Line "Guest Access" "OK" "Green"

        foreach ($line in ($r.ScriptOutput -split "`r?`n")) {
            if ($line -match "^PK=")     { $obj.PK = $line.Replace("PK=","").Trim() }
            if ($line -match "^KEK=")    { $obj.KEK2023 = $line.Replace("KEK=","").Trim() }
            if ($line -match "^DB=")     { $obj.DB2023 = $line.Replace("DB=","").Trim() }
            if ($line -match "^EV1801=") { $obj.Event1801 = $line.Replace("EV1801=","").Trim() }
            if ($line -match "^EV1769=") { $obj.Event1769 = $line.Replace("EV1769=","").Trim() }
            if ($line -match "^EV1799=") { $obj.Event1799 = $line.Replace("EV1799=","").Trim() }
            if ($line -match "^EV1808=") { $obj.Event1808 = $line.Replace("EV1808=","").Trim() }
        }

        Show-Line "PK" $obj.PK $(if($obj.PK -eq "OK"){"Green"}else{"Red"})
        Show-Line "KEK 2023" $obj.KEK2023 $(if($obj.KEK2023 -eq "Present"){"Green"}else{"Red"})
        Show-Line "DB 2023" $obj.DB2023 $(if($obj.DB2023 -eq "Present"){"Green"}else{"Yellow"})
        Show-Line "Event 1799" $obj.Event1799 $(if($obj.Event1799 -eq "Yes"){"Green"}else{"Gray"})
        Show-Line "Event 1808" $obj.Event1808 $(if($obj.Event1808 -eq "Yes"){"Green"}else{"Gray"})
        Show-Line "Event 1801" $obj.Event1801 $(if($obj.Event1801 -eq "No"){"Green"}else{"Red"})
        Show-Line "Event 1769" $obj.Event1769 $(if($obj.Event1769 -eq "No"){"Green"}else{"Red"})

        # NUEVA PRIORIDAD
        if ($obj.Event1808 -eq "Yes") {
            $obj.Assessment = "Healthy"
            $obj.Notes = "Fully updated (Event 1808)"
            Show-Line "RESULT" "Healthy (1808)" "Green"
        }
        elseif ($obj.Event1799 -eq "Yes") {
            $obj.Assessment = "Healthy"
            $obj.Notes = "Bootloader updated (1799)"
            Show-Line "RESULT" "Healthy (1799)" "Green"
        }
        elseif ($obj.PK -eq "Invalid" -and $obj.KEK2023 -eq "Missing") {
            $obj.Assessment = "Affected"
            Show-Line "RESULT" "Affected" "Red"
        }
        elseif ($obj.PK -eq "Invalid" -and $obj.KEK2023 -eq "Present") {
            $obj.Assessment = "Review"
            Show-Line "RESULT" "Review" "Yellow"
        }
        elseif ($obj.PK -eq "OK" -and $obj.KEK2023 -eq "Present" -and $obj.DB2023 -eq "Missing") {
            $obj.Assessment = "Pending DB"
            Show-Line "RESULT" "Pending DB" "Yellow"
        }
        elseif ($obj.PK -eq "OK" -and $obj.KEK2023 -eq "Present" -and $obj.DB2023 -eq "Present") {
            $obj.Assessment = "Healthy"
            Show-Line "RESULT" "Healthy" "Green"
        }
        else {
            $obj.Assessment = "Unknown"
            Show-Line "RESULT" "Unknown" "Yellow"
        }

    }
    catch {
        $obj.Assessment = "Unknown"
        $obj.Notes = $_.Exception.Message
        Show-Line "Guest Access" "Failed" "Red"
        Show-Line "RESULT" "Unknown" "Red"
    }

    $results += [pscustomobject]$obj
}

Write-Progress -Activity "Secure Boot Assessment" -Completed

$results | Export-Excel -Path $OutputXlsx -WorksheetName "Assessment" -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow

Write-Host "`nReporte generado: $OutputXlsx" -ForegroundColor Green

$results | Format-Table VMName,PK,KEK2023,DB2023,Event1799,Event1808,Assessment -AutoSize

Disconnect-VIServer -Server $vCenter -Confirm:$false 
