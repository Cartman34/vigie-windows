# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: format, paths, var
<#
    Intent: THE HARDWARE SHEET: what does not move -- machine, processor, memory sticks, disks, screens -- read from Windows and cached, because asking again costs seconds and answers the same.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# --- THE HARDWARE SHEET: what does not move ----------------------------------
#
# The second export asked for, the other being the state at this instant: the PHYSICAL
# characteristics of the machine. They are read once and kept: a memory module does not
# change between two refreshes, and the inventory costs several seconds (CIM over a dozen
# classes).
#
# Every section is independent and defensive: a CIM class absent or refused gives an empty
# section, never an error -- a partial sheet beats no sheet.
function Get-HardwareSpecs {
    param(
        [string]$Backend = (Get-BackendRoot),
        # A fresh reading: after a hardware change, or from the export.
        [switch]$Force
    )
    $cacheFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'hardware.json'
    if (-not $Force -and (Test-Path -LiteralPath $cacheFile)) {
        try {
            $j = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
            # A SHEET OF THE PREVIOUS SHAPE IS NOT MIGRATED, IT IS READ AGAIN. Its keys were French until 13/10;
            # every one of its values comes from the hardware, so one CIM pass rebuilds the whole of it. Nothing
            # is lost by dropping it -- unlike the record of something that HAPPENED, which is kept and read under
            # both names (wu-install.json). The absence of `machine.name` is the mark of the old shape.
            if (-not $j.machine -or -not $j.machine.name) { throw 'fiche de forme precedente' }
            $at = ConvertTo-UtcDate $j.at
            # Seven days: hardware does not change, but an eternal sheet would survive a new
            # disk or a new memory module without anybody knowing.
            if ($at -and ([datetime]::UtcNow - $at).TotalDays -lt 7) { return $j }
        } catch { }
    }

    function Read-CimClass { param([string]$classKey, [string]$Espace = 'root/cimv2')
        try { return @(Get-CimInstance -Namespace $Espace -ClassName $classKey -ErrorAction Stop) } catch { return @() }
    }
    $toGb = { param($octets) if ($octets) { [math]::Round(([double]$octets) / 1GB, 1) } else { $null } }

    $cs   = @(Read-CimClass 'Win32_ComputerSystem')   | Select-Object -First 1
    $bios = @(Read-CimClass 'Win32_BIOS')             | Select-Object -First 1
    $cb   = @(Read-CimClass 'Win32_BaseBoard')        | Select-Object -First 1
    $os   = @(Read-CimClass 'Win32_OperatingSystem')  | Select-Object -First 1
    $enc  = @(Read-CimClass 'Win32_SystemEnclosure')  | Select-Object -First 1

    # Laptop or desktop? The chassis type says so (8-14 and 30-32 mean mobile).
    $mobile = $false
    try {
        foreach ($t in @($enc.ChassisTypes)) {
            if ((8..14) -contains [int]$t -or (30..32) -contains [int]$t) { $mobile = $true }
        }
    } catch { }

    $machine = [ordered]@{
        name          = "$env:COMPUTERNAME"
        manufacturer    = "$($cs.Manufacturer)"
        model       = "$($cs.Model)"
        family      = "$($cs.SystemFamily)"
        form        = $(if ($mobile) { 'Portable' } else { 'Poste fixe' })
        serialNumber  = "$($bios.SerialNumber)"
        uuid         = "$((@(Read-CimClass 'Win32_ComputerSystemProduct') | Select-Object -First 1).UUID)"
        os           = "$($os.Caption)"
        osVersion    = "$($os.Version)"
        osArchitecture      = "$($os.OSArchitecture)"
        installedAt   = $(try { ([datetime]$os.InstallDate).ToString('o') } catch { '' })
    }

    $motherboard = [ordered]@{
        manufacturer = "$($cb.Manufacturer)"
        model    = "$($cb.Product)"
        version   = "$($cb.Version)"
        bios      = "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)"
        biosDate  = $(try { ([datetime]$bios.ReleaseDate).ToString('o') } catch { '' })
    }

    $processors = @(foreach ($c in (Read-CimClass 'Win32_Processor')) {
        [ordered]@{
            name       = "$($c.Name)".Trim()
            manufacturer = "$($c.Manufacturer)"
            cores    = [int]$c.NumberOfCores
            threads      = [int]$c.NumberOfLogicalProcessors
            frequency = [int]$c.MaxClockSpeed          # MHz
            socket    = "$($c.SocketDesignation)"
            cacheL3Kb = [int]$c.L3CacheSize
        }
    })

    # Memory type: the SMBIOS code, translated. A number tells nobody anything.
    $memoryTypes = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 34 = 'DDR5'; 35 = 'LPDDR4'; 36 = 'LPDDR5' }
    $memoryModules = @(foreach ($m in (Read-CimClass 'Win32_PhysicalMemory')) {
        $t = $null
        try { if ($memoryTypes.ContainsKey([int]$m.SMBIOSMemoryType)) { $t = $memoryTypes[[int]$m.SMBIOSMemoryType] } } catch { }
        [ordered]@{
            slot = "$($m.DeviceLocator)"
            sizeGb    = (& $toGb $m.Capacity)
            type        = $(if ($t) { $t } else { '' })
            speed     = [int]$m.Speed                # MT/s
            manufacturer   = "$($m.Manufacturer)".Trim()
            partNumber   = "$($m.PartNumber)".Trim()
        }
    })
    $memory = [ordered]@{
        totalGb   = (& $toGb $cs.TotalPhysicalMemory)
        sticks = $memoryModules
        # What the motherboard can take: useful when an upgrade is being considered.
        slots = [int]((@(Read-CimClass 'Win32_PhysicalMemoryArray') | Select-Object -First 1).MemoryDevices)
    }

    $disks = @(foreach ($d in (Read-CimClass 'MSFT_PhysicalDisk' 'root/microsoft/windows/storage')) {
        $bus = switch ([int]$d.BusType) { 7 { 'USB' } 8 { 'RAID' } 11 { 'SATA' } 17 { 'NVMe' } default { '' } }
        $media = switch ([int]$d.MediaType) { 3 { 'Disque dur' } 4 { 'SSD' } 5 { 'SCM' } default { '' } }
        [ordered]@{
            model    = "$($d.FriendlyName)".Trim()
            sizeGb  = (& $toGb $d.Size)
            type      = $media
            bus       = $bus
            health     = $(switch ([int]$d.HealthStatus) { 0 { 'Sain' } 1 { 'A surveiller' } 2 { 'Defaillant' } default { '' } })
            firmware  = "$($d.FirmwareVersion)"
            serialNumber = "$($d.SerialNumber)".Trim()
        }
    })
    # Fallback: on a machine with no Storage namespace, Win32_DiskDrive is enough.
    if (-not $disks.Count) {
        $disks = @(foreach ($d in (Read-CimClass 'Win32_DiskDrive')) {
            [ordered]@{ model = "$($d.Model)".Trim(); sizeGb = (& $toGb $d.Size)
                        type = ''; bus = "$($d.InterfaceType)"; health = ''
                        firmware = "$($d.FirmwareRevision)".Trim(); serialNumber = "$($d.SerialNumber)".Trim() }
        })
    }

    # VRAM IS NOT READ FROM AdapterRAM: that field is a signed 32-bit integer, it caps at
    # 4 GB and returns nonsense beyond it (an 8 GB RTX 4070 appears there with 4 GB, sometimes
    # less). The real value is in the driver's registry key, qwMemorySize, on 64 bits.
    $vramByName = @{}
    try {
        $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        # SilentlyContinue rather than Stop: one of this class's sub-keys is refused even to
        # an administrator ("Requested registry access is not allowed"), and with Stop the
        # enumeration stopped BEFORE the NVIDIA card -- the VRAM then fell back on AdapterRAM,
        # which caps at 4 GB. Seen on this very machine.
        foreach ($k in (Get-ChildItem -Path $classKey -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
            $pr = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
            if ($pr -and $pr.DriverDesc -and $pr.'HardwareInformation.qwMemorySize') {
                $vramByName["$($pr.DriverDesc)"] = [math]::Round(([double]$pr.'HardwareInformation.qwMemorySize') / 1GB, 1)
            }
        }
    } catch { }

    $graphics = @(foreach ($g in (Read-CimClass 'Win32_VideoController')) {
        $gpuName = "$($g.Name)".Trim()
        [ordered]@{
            name        = $gpuName
            vramGb     = $(if ($vramByName.ContainsKey($gpuName)) { $vramByName[$gpuName] } else { (& $toGb $g.AdapterRAM) })
            driver     = "$($g.DriverVersion)"
            driverDate = $(try { ([datetime]$g.DriverDate).ToString('o') } catch { '' })
            resolution = $(if ($g.CurrentHorizontalResolution) { "$($g.CurrentHorizontalResolution) x $($g.CurrentVerticalResolution)" } else { '' })
        }
    })

    # Monitors: WmiMonitorID returns arrays of codes, not strings.
    $decodeWmiText = { param($codes) if (-not $codes) { return '' }
        (-join ($codes | Where-Object { $_ -gt 0 } | ForEach-Object { [char][int]$_ })).Trim() }
    $screens = @(foreach ($e in (Read-CimClass 'WmiMonitorID' 'root/wmi')) {
        $size = ''
        [ordered]@{
            manufacturer = (& $decodeWmiText $e.ManufacturerName)
            model    = (& $decodeWmiText $e.UserFriendlyName)
            serial     = (& $decodeWmiText $e.SerialNumberID)
            year     = [int]$e.YearOfManufacture
        }
    })
    # Inches: a separate class (physical dimensions, in centimetres).
    $sizes = @(Read-CimClass 'WmiMonitorBasicDisplayParams' 'root/wmi')
    for ($i = 0; $i -lt $screens.Count -and $i -lt $sizes.Count; $i++) {
        try {
            $l = [double]$sizes[$i].MaxHorizontalImageSize
            $h = [double]$sizes[$i].MaxVerticalImageSize
            if ($l -gt 0 -and $h -gt 0) {
                $screens[$i]['inches'] = [math]::Round([math]::Sqrt($l * $l + $h * $h) / 2.54, 1)
            }
        } catch { }
    }

    # PHYSICAL network adapters.
    #
    # Win32_NetworkAdapter.PhysicalAdapter is NOT enough: it answers "yes" for Bluetooth PAN,
    # for VirtualBox and VMware adapters, and for WAN Miniport ones. Get-NetAdapter -Physical,
    # on the other hand, rests on the real device type -- it is used as a white list wherever
    # it is available.
    $physical = $null
    try { $physical = @((Get-NetAdapter -Physical -ErrorAction Stop).InterfaceDescription) } catch { }
    $network = @(foreach ($a in (Read-CimClass 'Win32_NetworkAdapter')) {
        if (-not $a.PhysicalAdapter) { continue }
        if (-not "$($a.MACAddress)") { continue }
        if ($physical -and ($physical -notcontains "$($a.Description)")) { continue }
        if (-not $physical -and "$($a.Name)" -match 'Virtual|Host-Only|Bluetooth|Miniport|Loopback') { continue }
        [ordered]@{
            name       = "$($a.Name)".Trim()
            manufacturer = "$($a.Manufacturer)".Trim()
            mac       = "$($a.MACAddress)"
            # Windows returns 0xFFFFFFFFFFFFFFFF when the link is not established, which gave
            # "9223372036855 Mb/s" on the sheet. Past 100 Gb/s the value means nothing: we
            # display nothing rather than an absurdity.
            maxSpeedMbps  = $(if ($a.Speed -and ([double]$a.Speed) -lt 1e11) { [math]::Round(([double]$a.Speed) / 1e6) } else { $null })   # Mb/s
        }
    })

    $battery = $null
    $bat = @(Read-CimClass 'Win32_Battery') | Select-Object -First 1
    if ($bat) {
        $full = @(Read-CimClass 'BatteryFullChargedCapacity' 'root/wmi') | Select-Object -First 1
        $battery = [ordered]@{
            name         = "$($bat.Name)".Trim()
            chemistry      = $(switch ([int]$bat.Chemistry) { 3 { 'Nickel-Cadmium' } 4 { 'Nickel-Hydrure' } 5 { 'Lithium-ion' } 6 { 'Zinc-air' } 7 { 'Lithium-polymere' } default { '' } })
            capacityMwh = $(if ($full) { [int]$full.FullChargedCapacity } else { $null })
            voltage     = $(if ($bat.DesignVoltage) { [int]$bat.DesignVoltage } else { $null })   # mV
        }
    }

    $sheet = [pscustomobject][ordered]@{
        at          = (Get-Date).ToUniversalTime().ToString('o')
        machine     = $machine
        motherboard   = $motherboard
        processors = $processors
        memory     = $memory
        disks     = $disks
        graphics  = $graphics
        screens      = $screens
        network      = $network
        battery    = $battery
    }
    try {
        $d = Split-Path $cacheFile -Parent
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        ($sheet | ConvertTo-Json -Depth 12) | Out-File -FilePath $cacheFile -Encoding UTF8
    } catch { }
    return $sheet
}
