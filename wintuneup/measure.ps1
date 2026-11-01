<#
  wintuneup - measure.ps1

  ONE state snapshot, identical every time, so before/after is comparable.
  Read-only. No admin. Takes ~35s (it settles first - see SKILL.md "Measuring").

    powershell -ExecutionPolicy Bypass -File measure.ps1              # settle 30s, then measure
    powershell -ExecutionPolicy Bypass -File measure.ps1 -Now         # skip settle (baseline only)
    powershell -ExecutionPolicy Bypass -File measure.ps1 -Inventory   # + About This PC counts

  Emits KEY=VALUE lines so successive runs diff cleanly.

  DELIBERATELY COUNTER-FREE. Get-Counter and the Win32_PerfFormattedData_* classes
  depend on the Perflib counter-name registry, which is a commonly corrupted part of
  Windows - when it is, every one of those calls returns empty and a naive script
  reports a perfectly idle machine. CPU here is derived from per-process CPU-time
  deltas, which always work and are locale-independent.
#>
[CmdletBinding()]
param([switch]$Now, [switch]$Inventory)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

if (-not $Now) { Start-Sleep -Seconds 30 }

$os  = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$lp  = (Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum

# CPU by process-time delta over a real interval. Idle (PID 0) excluded.
$before = @{}
Get-Process | Where-Object { $_.Id -ne 0 } | ForEach-Object { $before[$_.Id] = $_.CPU }
$sw = [Diagnostics.Stopwatch]::StartNew(); Start-Sleep -Seconds 3; $sw.Stop()
$elapsed = $sw.Elapsed.TotalSeconds
$rows = Get-Process | Where-Object { $_.Id -ne 0 } | ForEach-Object {
    $prev = if ($before.ContainsKey($_.Id)) { $before[$_.Id] } else { 0 }
    $d = $_.CPU - $prev
    if ($d -gt 0) { [PSCustomObject]@{ Name = $_.ProcessName; Pct = 100 * $d / $elapsed / $lp } }
}
$cpuTotal = [math]::Round((($rows | Measure-Object Pct -Sum).Sum), 1)

"TIMESTAMP=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
"UPTIME_HOURS={0}" -f [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)
"LOGICAL_CPUS=$lp"
"CPU_PCT=$cpuTotal"
"CPU_SAMPLE_SEC={0}" -f [math]::Round($elapsed,1)

$availMB  = [math]::Round($os.FreePhysicalMemory/1KB)
$totalMB  = [math]::Round($os.TotalVisibleMemorySize/1KB)
$commitMB = [math]::Round(($os.TotalVirtualMemorySize - $os.FreeVirtualMemory)/1KB)
$limitMB  = [math]::Round($os.TotalVirtualMemorySize/1KB)
"MEM_TOTAL_MB=$totalMB"
"MEM_AVAILABLE_MB=$availMB"
"MEM_USED_MB={0}" -f ($totalMB - $availMB)
"MEM_USED_PCT={0}" -f [math]::Round(100*($totalMB-$availMB)/$totalMB,1)
"COMMIT_MB=$commitMB"
"COMMIT_LIMIT_MB=$limitMB"
"COMMIT_PCT={0}" -f [math]::Round(100*$commitMB/$limitMB,1)
# COMMIT_PCT is the honest pressure metric. MEM_AVAILABLE_MB swings second to second
# because Windows opportunistically fills free RAM with cache - one reading proves nothing.
foreach ($pf in (Get-CimInstance Win32_PageFileUsage)) {
    "PAGEFILE_USED_PCT={0}" -f $(if ($pf.AllocatedBaseSize) { [math]::Round(100*$pf.CurrentUsage/$pf.AllocatedBaseSize) } else { 0 })
}

$procs = @(Get-Process | Where-Object { $_.Id -ne 0 })
"PROCESSES={0}" -f $procs.Count
"THREADS={0}"   -f ($procs | ForEach-Object { $_.Threads.Count } | Measure-Object -Sum).Sum
"HANDLES={0}"   -f ($procs | Measure-Object HandleCount -Sum).Sum

$c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
"C_FREE_GB={0}"  -f [math]::Round($c.FreeSpace/1GB,1)
"C_USED_PCT={0}" -f $(if ($c.Size) { [math]::Round(100*(1-$c.FreeSpace/$c.Size)) } else { 0 })

$tc = $rows | Sort-Object Pct -Descending | Select-Object -First 1
"TOP_CPU={0} {1}%" -f $tc.Name, [math]::Round($tc.Pct,1)
$tr = $procs | Group-Object ProcessName |
      ForEach-Object { [PSCustomObject]@{ N=$_.Name; MB=[math]::Round(($_.Group|Measure-Object WorkingSet64 -Sum).Sum/1MB); C=$_.Count } } |
      Sort-Object MB -Descending | Select-Object -First 1
"TOP_RAM={0} {1}MB across {2} proc" -f $tr.N, $tr.MB, $tr.C

if ($Inventory) {
    $cs = Get-CimInstance Win32_ComputerSystem
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    "MODEL={0} {1}" -f $cs.Manufacturer, $cs.Model
    "CPU_NAME={0}" -f $cpu.Name.Trim()
    "CORES={0}" -f (Get-CimInstance Win32_Processor | Measure-Object NumberOfCores -Sum).Sum
    "RAM_GB={0}" -f [math]::Round($cs.TotalPhysicalMemory/1GB,1)
    "OS={0}" -f $os.Caption
    "BUILD={0} {1}.{2}" -f $cv.DisplayVersion, $cv.CurrentBuild, $cv.UBR

    $runKeys = 0
    foreach ($r in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                   'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run',
                   'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run') {
        $k = Get-Item -LiteralPath $r; if ($k) { $runKeys += $k.GetValueNames().Count }
    }
    "STARTUP_RUN_KEYS=$runKeys"
    "STARTUP_FOLDER_ITEMS={0}" -f @(Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
                                                  "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup" -File).Count
    "SCHEDULED_TASKS_3P={0}" -f @(Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' }).Count
    "SERVICES_AUTO={0}"      -f @(Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' }).Count
    "SERVICES_RUNNING={0}"   -f @(Get-Service | Where-Object { $_.Status -eq 'Running' }).Count
    "DRIVERS_RUNNING={0}"    -f @(Get-CimInstance Win32_SystemDriver | Where-Object { $_.State -eq 'Running' }).Count

    $uni = @()
    foreach ($r in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                   'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                   'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        $uni += Get-ItemProperty $r | Where-Object { $_.DisplayName -and -not $_.SystemComponent }
    }
    "APPS_DESKTOP={0}" -f ($uni | Select-Object -ExpandProperty DisplayName -Unique).Count
    "APPS_STORE={0}"   -f @(Get-AppxPackage | Where-Object { -not $_.IsFramework }).Count

    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1
    "IP={0}" -f (Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4).IPAddress
    "ADAPTERS_UP={0}" -f @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }).Count
    "VPN_PROCS={0}" -f (@(foreach ($n in 'tailscaled','mullvad-daemon','wireguard','openvpn','nordvpn','warp-svc') {
        if (Get-Process -Name $n) { $n } }) -join ' ')
    $rb = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $rb += 'CBS' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $rb += 'WU' }
    "REBOOT_PENDING={0}" -f $(if ($rb) { $rb -join ',' } else { 'no' })
    # Perflib health: when this is broken every counter-based tool silently reports zeros.
    "PERFLIB_COUNTERS={0}" -f @((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\009').Counter).Count
}
