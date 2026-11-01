#Requires -Version 5.1
<#
Read-only heat and throttle check. Prints KEY=VALUE lines, so nobody needs a screenshot.
  thermal.ps1         Counters + nvidia-smi + HWiNFO sensors, if HWiNFO shares them.
  thermal.ps1 -Setup  Turns on HWiNFO sensor sharing in its INI (backup first) and starts it minimized.
                      Run elevated. Install HWiNFO first: winget install REALiX.HWiNFO
The free HWiNFO edition stops sharing after 12 hours. Re-run -Setup when SENSORS=NOT-SHARED.
#>
param([switch]$Setup, [int]$Seconds = 6)
$ErrorActionPreference = 'Continue'

function Out-Kv($k, $v) { "{0}={1}" -f $k, $v }

$HwExe = 'C:\Program Files\HWiNFO64\HWiNFO64.exe'
$HwIni = 'C:\Program Files\HWiNFO64\HWiNFO64.INI'

if ($Setup) {
    if (-not (Test-Path $HwExe)) { Out-Kv 'SETUP' 'HWINFO-NOT-INSTALLED'; exit 1 }
    if (Test-Path $HwIni) { Copy-Item $HwIni "$HwIni.tuneup-bak" -Force }
    $lines = if (Test-Path $HwIni) { @(Get-Content $HwIni) } else { @('[Settings]') }
    $want = [ordered]@{ SensorsOnly = 1; SensorsSM = 1; MinimalizeSensors = 1; MinimalizeMainWnd = 1; ShowWelcomeAndProgress = 0; AutoUpdate = 0 }
    foreach ($k in $want.Keys) {
        $found = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^$k=") { $lines[$i] = "$k=$($want[$k])"; $found = $true }
        }
        if (-not $found) {
            $at = [array]::IndexOf($lines, '[Settings]')
            if ($at -lt 0) { $lines = @('[Settings]') + $lines; $at = 0 }
            $lines = $lines[0..$at] + "$k=$($want[$k])" + $(if ($at + 1 -lt $lines.Count) { $lines[($at + 1)..($lines.Count - 1)] })
        }
    }
    Set-Content -Path $HwIni -Value $lines -Encoding ASCII
    # Restart so HWiNFO reads the INI. Kill by PID.
    Get-Process HWiNFO64 -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Start-Sleep -Seconds 2
    Start-Process $HwExe -WindowStyle Minimized
    # HWiNFO scans hardware first. Sharing starts about 30 s later on large systems.
    $ready = $false
    for ($i = 0; $i -lt 60 -and -not $ready; $i++) {
        Start-Sleep -Seconds 1
        try { [IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting('Global\HWiNFO_SENS_SM2', [IO.MemoryMappedFiles.MemoryMappedFileRights]::Read).Dispose(); $ready = $true } catch {}
    }
    Out-Kv 'SETUP' $(if ($ready) { 'DONE' } else { 'NOT-SHARED-AFTER-60S' })
}

# 1. Counters: no install, no admin. Above 100 = boost. Well under 100 while busy = held back.
$paths = '\Processor Information(_Total)\% Processor Performance', '\Processor(_Total)\% Processor Time'
$samples = (Get-Counter -Counter $paths -SampleInterval 1 -MaxSamples $Seconds -ErrorAction SilentlyContinue).CounterSamples
$perf = ($samples | Where-Object Path -like '*processor performance' | Measure-Object CookedValue -Average).Average
$use  = ($samples | Where-Object Path -like '*processor time' | Measure-Object CookedValue -Average).Average
Out-Kv 'CPU_SPEED_PCT' ('{0:N0}' -f $perf)
Out-Kv 'CPU_USE_PCT'   ('{0:N0}' -f $use)

# 2. NVIDIA GPU: no install beyond the driver.
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    $g = & nvidia-smi --query-gpu=name,pstate,temperature.gpu,power.draw,clocks.gr,utilization.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1
    if ($g) {
        $p = $g -split ',\s*'
        Out-Kv 'GPU_NAME' $p[0]; Out-Kv 'GPU_PSTATE' $p[1]; Out-Kv 'GPU_TEMP_C' $p[2]
        Out-Kv 'GPU_WATTS' $p[3]; Out-Kv 'GPU_MHZ' $p[4]; Out-Kv 'GPU_USE_PCT' $p[5]
    }
}

# 3. HWiNFO shared memory. Layout: HWiNFO SDK, HWiNFO_SENSORS_SHARED_MEM2, packed.
function Read-HwInfo {
    $map = $null
    foreach ($n in 'Global\HWiNFO_SENS_SM2', 'HWiNFO_SENS_SM2') {
        try { $map = [IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting($n, [IO.MemoryMappedFiles.MemoryMappedFileRights]::Read); break } catch {}
    }
    if (-not $map) { return $null }
    $v = $map.CreateViewAccessor(0, 0, [IO.MemoryMappedFiles.MemoryMappedFileAccess]::Read)
    try {
        if ($v.ReadUInt32(0) -ne 0x53695748) { return $null }   # 'HWiS'; 'DEAD' after the free-edition limit
        $sOff = $v.ReadUInt32(20); $sSize = $v.ReadUInt32(24); $sNum = $v.ReadUInt32(28)
        $rOff = $v.ReadUInt32(32); $rSize = $v.ReadUInt32(36); $rNum = $v.ReadUInt32(40)
        $text = {
            param($at, $len)
            $b = New-Object byte[] $len
            [void]$v.ReadArray($at, $b, 0, $len)
            $end = [array]::IndexOf($b, [byte]0); if ($end -lt 0) { $end = $len }
            [Text.Encoding]::Default.GetString($b, 0, $end)
        }
        $sensors = for ($i = 0; $i -lt $sNum; $i++) { & $text ($sOff + $i * $sSize + 8) 128 }
        for ($i = 0; $i -lt $rNum; $i++) {
            $at = $rOff + $i * $rSize
            [pscustomobject]@{
                Type   = $v.ReadUInt32($at)            # 1 temp, 3 fan, 5 power, 6 clock, 7 usage, 8 other
                Sensor = $sensors[$v.ReadUInt32($at + 4)]
                Label  = & $text ($at + 12) 128
                Unit   = & $text ($at + 268) 16
                Value  = $v.ReadDouble($at + 284)
            }
        }
    } finally { $v.Dispose(); $map.Dispose() }
}

$cpuTemp = $null; $cpuWatts = $null; $limit = $null; $eff = $null
$r = @(Read-HwInfo)
if ($r.Count -eq 0 -or $null -eq $r[0]) {
    Out-Kv 'SENSORS' 'NOT-SHARED (install HWiNFO, then run -Setup; free edition stops after 12 h)'
} else {
    function Pick($type, $pattern) { $r | Where-Object { $_.Type -eq $type -and $_.Label -match $pattern } | Select-Object -First 1 }
    $t = Pick 1 'Tctl/Tdie|CPU Package$|^CPU \(Tctl'
    if ($t) { $cpuTemp = $t.Value; Out-Kv 'CPU_TEMP_C' ('{0:N1}' -f $cpuTemp) }
    $w = Pick 5 '^CPU Package Power$'
    if ($w) { $cpuWatts = $w.Value; Out-Kv 'CPU_WATTS' ('{0:N1}' -f $cpuWatts) }
    $e = Pick 6 'Average Effective Clock'
    if ($e) { $eff = $e.Value; Out-Kv 'CPU_EFFECTIVE_MHZ' ('{0:N0}' -f $eff) }
    foreach ($q in @{ k = 'CPU_THERMAL_LIMIT_PCT'; p = '^Thermal Limit$' }, @{ k = 'CPU_PPT_SLOW_LIMIT_PCT'; p = 'PPT SLOW Limit' }) {
        $x = $r | Where-Object Label -match $q.p | Select-Object -First 1
        if ($x) { Out-Kv $q.k ('{0:N0}' -f $x.Value); if ($q.k -eq 'CPU_THERMAL_LIMIT_PCT') { $limit = $x.Value } }
    }
    $flags = @($r | Where-Object { $_.Label -match 'Thermal Throttling|Power Limit Exceeded' -and $_.Value -ne 0 } | ForEach-Object Label)
    Out-Kv 'THROTTLE_FLAGS' $(if ($flags.Count) { $flags -join '; ' } else { 'none' })
    $ram = $r | Where-Object { $_.Type -eq 1 -and $_.Sensor -match 'DIMM' -and $_.Label -match 'SPD Hub|DIMM' } | Measure-Object Value -Maximum
    if ($ram.Count) { Out-Kv 'RAM_TEMP_C' ('{0:N1}' -f $ram.Maximum) }
    $vrm = $r | Where-Object { $_.Type -eq 1 -and $_.Label -match 'VRM' } | Measure-Object Value -Maximum
    if ($vrm.Count) { Out-Kv 'VRM_TEMP_C' ('{0:N1}' -f $vrm.Maximum) }
    $disk = $r | Where-Object { $_.Type -eq 1 -and $_.Sensor -match 'S\.M\.A\.R\.T|NVMe' -and $_.Label -match 'Drive Temperature$' } | Measure-Object Value -Maximum
    if ($disk.Count) { Out-Kv 'DISK_TEMP_C' ('{0:N1}' -f $disk.Maximum) }
    $fans = @($r | Where-Object { $_.Type -eq 3 })
    Out-Kv 'FANS_FOUND' $fans.Count
    foreach ($f in $fans) { Out-Kv ("FAN {0}" -f $f.Label) ('{0:N0} {1}' -f $f.Value, $f.Unit) }
    Out-Kv 'SENSORS' $(if ($t) { 'OK' } else { 'NO-CPU-TEMP' })
}

# Verdict. A symptom to verify, not a final diagnosis.
$verdict = if ($null -eq $cpuTemp) { 'TEMP-UNKNOWN' } else { 'NO-SIGN-OF-HEAT-LIMIT' }
if ($null -ne $cpuTemp -and $cpuTemp -ge 95) {
    $verdict = if ($null -ne $cpuWatts -and $cpuWatts -lt 80) { 'HOT-AT-LOW-POWER (cooling problem: dust, fan, paste, blocked vents)' } else { 'HOT-UNDER-LOAD (compare with load before calling it a fault)' }
} elseif ($null -eq $cpuTemp -and $perf -lt 80) {
    $verdict = 'SPEED-LOW-TEMP-UNKNOWN (read sensors before naming heat)'
} elseif ($null -ne $cpuTemp -and $perf -lt 80) {
    $verdict = 'SPEED-LOW-NOT-HOT (look at power limits and firmware)'
}
Out-Kv 'THERMAL_VERDICT' $verdict
