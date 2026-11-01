<#
  wintuneup scan - READ ONLY. Changes nothing. Does NOT require Administrator.

  Emits section-delimited findings for Claude to interpret. Sections that genuinely
  need elevation say "NEEDS-ADMIN" rather than reporting a false clean.

    powershell -ExecutionPolicy Bypass -File scan.ps1
    powershell -ExecutionPolicy Bypass -File scan.ps1 -Deep    # + recursive disk sizing (slow)
#>
[CmdletBinding()]
param([switch]$Deep)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

function Section($t) { "`n===== $t =====" }   # NOT H: that is a built-in alias for Get-History and silently wins

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---------------------------------------------------------------------------
# Shared helper: pull the real executable out of a command line.
#
# THIS IS THE #1 FALSE-POSITIVE SOURCE. Program Files paths contain spaces, so
# splitting a command line on whitespace turns one healthy entry into three
# "missing files". Parse the quoted token first; only then fall back to a
# non-greedy match up to the first executable extension.
# ---------------------------------------------------------------------------
function Get-ExePath([string]$cmd) {
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($cmd.Trim())
    # Some Run values are wrapped in quotes AND backslash-escaped inside:
    #     "\"C:\path\app.exe\" --startup"
    # Unwrap first, or the quoted-token regex below captures a lone backslash and the
    # entry gets reported as an orphan pointing at "\".
    if ($c -match '^"\\"') { $c = ($c -replace '^"','' -replace '"$','') -replace '\\"','"' }
    if ($c -match '^\s*"([^"]+)"')                                         { return $matches[1] }
    if ($c -match '^\s*([A-Za-z]:\\.*?\.(?:exe|com|bat|cmd|scr|dll|msc))(?:\s|,|$)') { return $matches[1] }
    if ($c -match '^\s*(\S+\.(?:exe|com|bat|cmd|scr))(?:\s|$)')            { return $matches[1] }
    return $null
}

# A bare name like "OneDrive.exe" resolves via PATH; treat as present if found.
function Test-ExeMissing([string]$exe) {
    if (-not $exe) { return $false }                       # unparseable != missing
    if (Test-Path -LiteralPath $exe)                       { return $false }
    if ($exe -notmatch '[\\/]' -and (Get-Command $exe -ErrorAction SilentlyContinue)) { return $false }
    return $true
}

Section "IDENTITY"
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
"model={0} {1}" -f $cs.Manufacturer, $cs.Model
"cpu={0}" -f $cpu.Name
"cores={0} logical={1}" -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors
"ram_gb={0}" -f [math]::Round($cs.TotalPhysicalMemory/1GB,1)
"windows={0}" -f $os.Caption
"release={0} build={1}.{2}" -f $cv.DisplayVersion, $cv.CurrentBuild, $cv.UBR
"installed={0}" -f $os.InstallDate
$up = (Get-Date) - $os.LastBootUpTime
"uptime_hours={0}  lastboot={1}" -f [math]::Round($up.TotalHours,1), $os.LastBootUpTime
"elevated=$IsAdmin"
if ($up.TotalMinutes -lt 10) { "NOTE: uptime under 10 minutes - every load/CPU number below is a BOOT BURST, not a steady state." }

Section "PENDING_REBOOT"
# Check this FIRST. A machine with a pending reboot measures worse at everything,
# and 'fixing' that is one restart, not a tune-up.
$rb = @()
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $rb += 'CBS servicing' }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $rb += 'Windows Update' }
$pfr = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations).PendingFileRenameOperations
if ($pfr) { $rb += "PendingFileRenameOperations ($($pfr.Count) entries)" }
if ($rb) { "PENDING: " + ($rb -join ', ') } else { "none pending" }

Section "PERFLIB_HEALTH"
# Check this BEFORE any CPU number. The Perflib counter-name registry is a commonly
# corrupted piece of Windows. When it is empty, Get-Counter and every
# Win32_PerfFormattedData_* class return NOTHING - so a counter-based script reports a
# perfectly idle machine no matter how loaded it is, and Task Manager's App History,
# Resource Monitor and third-party monitors all show zeros. Rebuild: `lodctr /R`.
$pc = @((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\009').Counter).Count
"perflib_counter_strings=$pc"
if ($pc -lt 100) { "BROKEN: counter name registry is empty. Get-Counter and Win32_PerfFormattedData_* are dead." }
else { "ok" }

Section "CPU"
# Derived from per-process CPU-time deltas, NOT perf counters - see PERFLIB_HEALTH.
# This method works on every Windows box and is locale-independent.
$lp = (Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum
$before = @{}
Get-Process | Where-Object { $_.Id -ne 0 } | ForEach-Object { $before[$_.Id] = $_.CPU }
$sw = [Diagnostics.Stopwatch]::StartNew(); Start-Sleep -Seconds 3; $sw.Stop()
$el = $sw.Elapsed.TotalSeconds
$cpuRows = Get-Process | Where-Object { $_.Id -ne 0 } | ForEach-Object {
    $prev = if ($before.ContainsKey($_.Id)) { $before[$_.Id] } else { 0 }
    $d = $_.CPU - $prev
    if ($d -gt 0) { [PSCustomObject]@{ Name=$_.ProcessName; Pct=100*$d/$el/$lp; MB=[math]::Round($_.WorkingSet64/1MB) } }
}
$allProc = @(Get-Process | Where-Object { $_.Id -ne 0 })
"logical_cpus={0}  sample_sec={1}" -f $lp, [math]::Round($el,1)
"cpu_total_pct={0}" -f [math]::Round((($cpuRows | Measure-Object Pct -Sum).Sum),1)
"processes={0}  threads={1}  handles={2}" -f $allProc.Count,
    ($allProc | ForEach-Object { $_.Threads.Count } | Measure-Object -Sum).Sum,
    ($allProc | Measure-Object HandleCount -Sum).Sum
"INTERPRET: a 3-second sample catches steady load, not bursts. Sample twice, minutes apart,"
"           before calling anything a permanent problem."

Section "MEMORY_AND_PAGING"
$availMB  = [math]::Round($os.FreePhysicalMemory/1KB)
$totalMB  = [math]::Round($os.TotalVisibleMemorySize/1KB)
$commitMB = [math]::Round(($os.TotalVirtualMemorySize - $os.FreeVirtualMemory)/1KB)
$limitMB  = [math]::Round($os.TotalVirtualMemorySize/1KB)
"physical_total_mb={0}  available_mb={1}  used_pct={2}" -f $totalMB, $availMB, [math]::Round(100*($totalMB-$availMB)/$totalMB,1)
"commit_mb={0}  commit_limit_mb={1}  commit_pct={2}" -f $commitMB, $limitMB, [math]::Round(100*$commitMB/$limitMB,1)
"INTERPRET: commit_pct is the honest pressure metric. available_mb swings wildly because Windows"
"           opportunistically fills free RAM with cache - a single reading proves nothing."
foreach ($pf in (Get-CimInstance Win32_PageFileUsage)) {
    "pagefile={0} alloc_mb={1} used_mb={2} peak_mb={3}" -f $pf.Name, $pf.AllocatedBaseSize, $pf.CurrentUsage, $pf.PeakUsage
}

Section "TOP_CPU"
$cpuRows | Sort-Object Pct -Descending | Select-Object -First 12 |
    ForEach-Object { "  {0,6:N1}%  {1,7} MB  {2}" -f $_.Pct, $_.MB, $_.Name }

Section "TOP_RAM"
# Group by name: browsers and Electron apps fragment across dozens of helper processes.
# One Chrome line at 300 MB hides 2 GB spread over 40 children.
Get-Process | Group-Object ProcessName | ForEach-Object {
    [PSCustomObject]@{ Name=$_.Name; MB=[math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum/1MB); N=$_.Count }
} | Sort-Object MB -Descending | Select-Object -First 15 |
    ForEach-Object { "  {0,7} MB  {1,3} proc  {2}" -f $_.MB, $_.N, $_.Name }

Section "STARTUP_ENTRIES"
# The Windows analog of orphaned launchd plists, and usually the highest-value finding.
# Four independent anchors - miss one and the thing you 'removed' comes back at boot:
#   1 Run keys (HKLM + HKCU, incl. Wow6432Node)   2 Startup folders
#   3 Scheduled Tasks (next section)              4 Auto-start services (section after)
$approved = @{}
foreach ($ap in @(
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder')) {
    $k = Get-Item -LiteralPath $ap
    if ($k) { foreach ($n in $k.GetValueNames()) {
        $b = $k.GetValue($n)
        # byte[0] even = enabled, odd (2/3) = disabled by the user in Task Manager
        if ($b -is [byte[]] -and $b.Length) { $approved[$n] = if ($b[0] % 2 -eq 0) { 'enabled' } else { 'DISABLED' } }
    } }
}
foreach ($root in @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce')) {
    $k = Get-Item -LiteralPath $root
    if (-not $k) { continue }
    "-- $root --"
    foreach ($n in $k.GetValueNames()) {
        $val   = [string]$k.GetValue($n)
        $exe   = Get-ExePath $val
        $state = if ($approved.ContainsKey($n)) { $approved[$n] } else { 'enabled' }
        $flag  = if (Test-ExeMissing $exe) { '  <-- ORPHAN: target missing' } else { '' }
        "  [{0}] {1}`n        cmd: {2}`n        exe: {3}{4}" -f $state, $n, $val, $exe, $flag
    }
}
foreach ($sf in @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
                  "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup")) {
    "-- $sf --"
    Get-ChildItem -LiteralPath $sf -File | ForEach-Object {
        $state = if ($approved.ContainsKey($_.Name)) { $approved[$_.Name] } else { 'enabled' }
        "  [{0}] {1}" -f $state, $_.Name
    }
}
"(entries marked DISABLED are already off - do not offer to disable them again)"

Section "SCHEDULED_TASKS"
# Non-Microsoft tasks. An uninstalled app's leftover task is the direct equivalent of an
# orphaned launchd job: it still fires at every boot/login for years.
Get-ScheduledTask | Where-Object {
    $_.TaskPath -notlike '\Microsoft\*' -and $_.TaskPath -ne '\Microsoft\'
} | Sort-Object TaskPath, TaskName | ForEach-Object {
    $t    = $_
    $acts = @($t.Actions | Where-Object { $_.Execute })
    $miss = @()
    foreach ($a in $acts) {
        $e = Get-ExePath $a.Execute
        if (Test-ExeMissing $e) { $miss += $e }
    }
    $trig = ($t.Triggers | ForEach-Object { $_.CimClass.CimClassName -replace 'MSFT_Task|Trigger','' }) -join ','
    $tag  = if ($t.State -eq 'Disabled') { 'DISABLED' } elseif ($miss) { 'ORPHAN  ' } else { 'ok      ' }
    "  [{0}] {1}{2}   state={3} trig={4}" -f $tag, $t.TaskPath, $t.TaskName, $t.State, $trig
    foreach ($a in $acts) { "           run: {0} {1}" -f $a.Execute, $a.Arguments }
    foreach ($m in $miss) { "           MISSING: {0}" -f $m }
}
"(no ORPHAN lines above = every non-Microsoft task still points at a real file)"

Section "AUTOSTART_SERVICES"
# Missing-exe detection lifted from WinHealthSuite. Its key lesson: svchost-hosted
# services all share svchost.exe, so a naive check flags dozens of healthy services.
Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' } | Sort-Object Name | ForEach-Object {
    $exe = Get-ExePath $_.PathName
    if ($exe -match 'svchost\.exe$') { return }                     # shared host, never missing
    $ms  = Test-ExeMissing $exe
    $sig = if ($exe -match '(?i)\\Windows\\') { 'ms' } else { '3P' }
    if ($ms -or $sig -eq '3P') {
        $tag = if ($ms) { 'BROKEN' } else { '  3P  ' }
        "  [{0}] {1,-34} state={2,-8} {3}" -f $tag, $_.Name, $_.State, $exe
    }
}
"(BROKEN = auto-start service whose executable is gone: a failed uninstall, still retried every boot)"

Section "SERVICE_ERRORS_24H"
$since = (Get-Date).AddHours(-24)
$scm = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'; Level=1,2; StartTime=$since}
if (-not $scm) { "no service errors in 24h (or System log unreadable without admin)" }
else {
    "total service error events: {0}" -f @($scm).Count
    $scm | ForEach-Object { if ($_.Message -match 'The (.+?) service') { $matches[1] } } |
        Group-Object | Sort-Object Count -Descending | Select-Object -First 8 |
        ForEach-Object { "  {0,5}x  {1}" -f $_.Count, $_.Name }
    "(>=50 events for one service in 24h = crash-looping, not a blip)"
}

Section "SHELL_EXTENSIONS"
# Explorer loads every one of these in-process. A slow right-click or a hanging
# Explorer is almost always a third-party context-menu handler, and it is invisible
# in Task Manager because the cost shows up as explorer.exe.
$seen = @{}
foreach ($h in @(
    'HKLM:\SOFTWARE\Classes\*\shellex\ContextMenuHandlers',
    'HKLM:\SOFTWARE\Classes\Directory\shellex\ContextMenuHandlers',
    'HKLM:\SOFTWARE\Classes\Directory\Background\shellex\ContextMenuHandlers',
    'HKLM:\SOFTWARE\Classes\Folder\shellex\ContextMenuHandlers',
    'HKLM:\SOFTWARE\Classes\AllFilesystemObjects\shellex\ContextMenuHandlers')) {
    Get-ChildItem -LiteralPath $h | ForEach-Object {
        $clsid = [string](Get-ItemProperty -LiteralPath $_.PSPath).'(default)'
        if (-not $clsid -or $seen.ContainsKey("$($_.PSChildName)|$clsid")) { return }
        $seen["$($_.PSChildName)|$clsid"] = 1
        $dll = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Classes\CLSID\$clsid\InprocServer32").'(default)'
        $dll = if ($dll) { [Environment]::ExpandEnvironmentVariables($dll.Trim('"')) } else { $null }
        $ms  = $dll -match '(?i)\\Windows\\'
        if (-not $ms) {
            $flag = if ($dll -and -not (Test-Path -LiteralPath $dll)) { '  <-- DLL MISSING' } else { '' }
            "  {0,-30} {1}{2}" -f $_.PSChildName, $dll, $flag
        }
    }
}
"(Microsoft-owned handlers filtered out; what remains is third-party Explorer load)"

Section "SECURITY_STACK"
# Two real-time scanners inspecting each other's file I/O is one of the biggest
# real-world Windows slowdowns. But Defender demotes itself to passive when a third
# party registers, so check AMRunningMode before claiming a conflict exists.
$mp = Get-MpComputerStatus
if ($mp) {
    "defender_running_mode={0}" -f $mp.AMRunningMode
    "defender_realtime={0}  antivirus_enabled={1}" -f $mp.RealTimeProtectionEnabled, $mp.AntivirusEnabled
    "defender_sig_age_days={0}  last_quick_scan={1}" -f $mp.AntivirusSignatureAge, $mp.QuickScanEndTime
} else { "Get-MpComputerStatus unavailable" }
$av = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct
if ($av) { "registered AV products:"; $av | ForEach-Object { "  {0}  ({1})" -f $_.displayName, $_.pathToSignedProductExe } }
"defender exclusions (a missing dev-folder exclusion is why MsMpEng pegs a CPU):"
$mpp = Get-MpPreference
if ($mpp) {
    "  paths: {0}"      -f (($mpp.ExclusionPath      -join '; ') -replace '^$','(none)')
    "  processes: {0}"  -f (($mpp.ExclusionProcess   -join '; ') -replace '^$','(none)')
    "  extensions: {0}" -f (($mpp.ExclusionExtension -join '; ') -replace '^$','(none)')
}

Section "AUDIO"
# audiodg.exe hosts every audio-effect APO in-process - the direct analog of coreaudiod
# loading every HAL driver. Many virtual/effect drivers = one pegged core.
$adg = $cpuRows | Where-Object { $_.Name -eq 'audiodg' }
"audiodg_cpu_pct={0}" -f $(if ($adg) { [math]::Round($adg.Pct,1) } elseif (Get-Process audiodg) { '0 (running, idle)' } else { 'not running' })
"audio devices / virtual cables:"
Get-CimInstance Win32_PnPEntity -Filter "PNPClass='MEDIA' OR PNPClass='AudioEndpoint'" |
    Where-Object { $_.Manufacturer -notmatch '(?i)^Microsoft$' } |
    Select-Object -ExpandProperty Name -Unique | ForEach-Object { "  $_" }

Section "DISK"
Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Sort-Object DeviceID | ForEach-Object {
    "  {0} {1,-14} {2,8} GB free / {3,8} GB total  ({4}%)" -f $_.DeviceID, $_.VolumeName,
        [math]::Round($_.FreeSpace/1GB,1), [math]::Round($_.Size/1GB,1),
        $(if ($_.Size) { [math]::Round(100*(1-$_.FreeSpace/$_.Size)) } else { 0 })
}
"-- physical disks (bus type decides if a relocation target is safe) --"
foreach ($pd in Get-PhysicalDisk) {
    $bus = (Get-Disk -Number $pd.DeviceId).BusType
    $kind = if ($bus -in @('USB','SD','MMC','1394','Fibre Channel')) { 'REMOVABLE' } else { 'internal' }
    "  disk{0} {1,-30} {2,-6} {3,-9} health={4}" -f $pd.DeviceId, $pd.FriendlyName, $bus, $kind, $pd.HealthStatus
}
"-- shadow copy / restore point store (the Windows analog of APFS snapshots pinning space) --"
if ($IsAdmin) { cmd /c "vssadmin list shadowstorage /for=C: 2>&1" | Select-String 'Used|Allocated|Maximum' | ForEach-Object { "  " + $_.ToString().Trim() } }
else { "  NEEDS-ADMIN: vssadmin requires elevation. Store size UNKNOWN - do not report it as clean." }
"-- reclaim candidates --"
foreach ($p in @("$env:TEMP", 'C:\Windows\Temp', 'C:\Windows\SoftwareDistribution\Download',
                 'C:\Windows\Installer', 'C:\Windows.old',
                 'C:\ProgramData\Microsoft\Windows\DeliveryOptimization')) {
    if (Test-Path -LiteralPath $p) {
        $gb = [math]::Round((Get-ChildItem -LiteralPath $p -Recurse -File -Force | Measure-Object Length -Sum).Sum/1GB,2)
        "  {0,-58} {1,7} GB" -f $p, $gb
    }
}
if ($Deep) {
    "-- large user directories (junction-aware: reparse points are NOT counted against C:) --"
    foreach ($p in @("$env:LOCALAPPDATA", "$env:APPDATA", "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Documents")) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $it = Get-Item -LiteralPath $p -Force
        if (($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { "  {0,-58} -> JUNCTION to {1}" -f $p, $it.Target; continue }
        $gb = [math]::Round((Get-ChildItem -LiteralPath $p -Recurse -File -Force | Measure-Object Length -Sum).Sum/1GB,2)
        "  {0,-58} {1,7} GB" -f $p, $gb
    }
} else { "  (run with -Deep for recursive user-directory sizing; it is slow)" }

Section "THERMAL"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'thermal.ps1') -Seconds 3 2>&1

Section "POWER"
$plan = powercfg /getactivescheme
"active_plan=$plan"
"(a laptop-style Balanced/Power-saver plan on a desktop caps turbo and parks cores)"

Section "NETWORK_STATE"
# Identify the adapter by the routing table, not by 'first one that's Up'. With WiFi and
# Ethernet both connected, interface status alone names the wrong one.
$route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1
$ifIdx = $route.InterfaceIndex
$ad    = Get-NetAdapter -InterfaceIndex $ifIdx
"active_adapter={0} ({1})  ifIndex={2}" -f $ad.Name, $ad.InterfaceDescription, $ifIdx
"link_speed={0}  mtu={1}" -f $ad.LinkSpeed, (Get-NetIPInterface -InterfaceIndex $ifIdx -AddressFamily IPv4).NlMtu
"ipv4={0}" -f (Get-NetIPAddress -InterfaceIndex $ifIdx -AddressFamily IPv4).IPAddress
"gateway={0}" -f $route.NextHop
"dns={0}" -f ((Get-DnsClientServerAddress -InterfaceIndex $ifIdx -AddressFamily IPv4).ServerAddresses -join ', ')
"-- all adapters (each virtual stack adds routing/MTU complexity) --"
Get-NetAdapter | Sort-Object Status, Name | ForEach-Object {
    "  {0,-8} {1,-28} {2}" -f $_.Status, $_.Name, $_.InterfaceDescription
}
"-- VPN / tunnel processes --"
foreach ($n in 'tailscaled','tailscale-ipn','mullvad-daemon','wireguard','openvpn','nordvpn','expressvpn','ZeroTier One','warp-svc','Proton') {
    if (Get-Process -Name $n) { "  running: $n" }
}
"-- proxy config (an orphaned proxy from an uninstalled tool silently breaks browsing) --"
$px = Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings'
"  ProxyEnable={0}  ProxyServer={1}  AutoConfigURL={2}" -f $px.ProxyEnable, $px.ProxyServer, $px.AutoConfigURL

Section "NETWORK_TUNABLES"
# 'Optimizer' apps and old forum guides wreck these. Windows defaults are correct
# for essentially every modern connection.
netsh int tcp show global | Where-Object { $_ -match ':' } | ForEach-Object { "  " + $_.Trim() }
"expected defaults: Receive Window Auto-Tuning Level = normal, ECN = disabled,"
"                   RSS = enabled, Chimney Offload = disabled"
"-- per-interface MTU (1500 = normal ethernet; below that means a tunnel is clamping) --"
netsh int ipv4 show subinterfaces | Where-Object { $_ -match '\d' } | ForEach-Object { "  " + $_.Trim() }

Section "DNS_HEALTH"
# Cache-aware and load-aware, same discipline as the mac scan:
#   - random never-seen labels, because a cached name CANNOT fail
#   - two timeouts, because failures that shrink as the timeout grows mean this PC
#     is too loaded to answer in time, NOT that the resolver is bad
$gw = $route.NextHop
foreach ($srv in @($gw, '1.1.1.1')) {
    if (-not $srv -or $srv -eq '0.0.0.0') { continue }
    foreach ($t in 1, 5) {
        $fail = 0
        for ($i = 1; $i -le 10; $i++) {
            $q = "q$t-$i-$(Get-Random -Maximum 999999).example.com"
            $out = cmd /c "nslookup -timeout=$t -type=A $q $srv 2>&1"
            if ($out -match 'timed out|no response|Non-existent domain' -and $out -match 'timed out|no response') { $fail++ }
        }
        "  {0} @{1}s timeout: {2}/10 failed" -f $srv, $t, $fail
    }
}
"INTERPRET: NXDOMAIN is a SUCCESSFUL lookup (the server answered). Only timeouts count."
"           Failures shrinking as timeout grows = this PC is starved, not the resolver."

Section "INTERNET_PATH"
"-- first two hops (hop1 local-fast + hop2 far-slow = a tunnel on the router) --"
(tracert -d -h 2 -w 1000 1.1.1.1) | Select-Object -Skip 2 | ForEach-Object { "  " + $_.Trim() } | Where-Object { $_ -match '\d' }
"-- public exit --"
try { $ii = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -TimeoutSec 8
      "  ip={0} city={1} region={2} org={3}" -f $ii.ip, $ii.city, $ii.region, $ii.org } catch { "  (unreachable)" }
"-- 1 MB down vs 1 MB up (upload dying while download is fine = MTU/MSS on a tunnel) --"
try { $sw=[Diagnostics.Stopwatch]::StartNew()
      $null = Invoke-WebRequest 'https://speed.cloudflare.com/__down?bytes=1000000' -TimeoutSec 30 -UseBasicParsing
      "  GET  1MB down: OK ({0} ms)" -f $sw.ElapsedMilliseconds } catch { "  GET  1MB down: FAIL - $($_.Exception.Message)" }
try { $body=New-Object byte[] 1000000; (New-Object Random).NextBytes($body); $sw=[Diagnostics.Stopwatch]::StartNew()
      $null = Invoke-WebRequest 'https://speed.cloudflare.com/__up' -Method Post -Body $body -TimeoutSec 30 -UseBasicParsing
      "  POST 1MB up:   OK ({0} ms)" -f $sw.ElapsedMilliseconds } catch { "  POST 1MB up:   RESET - $($_.Exception.Message)" }

Section "DRIVERS"
if ($IsAdmin) {
    "-- third-party filter drivers (each one sits in the file I/O path) --"
    fltmc filters | ForEach-Object { "  " + $_.Trim() } | Where-Object { $_ }
} else { "  NEEDS-ADMIN: fltmc requires elevation - filter driver list UNKNOWN." }
"-- non-Microsoft kernel drivers currently running --"
Get-CimInstance Win32_SystemDriver | Where-Object { $_.State -eq 'Running' -and $_.PathName -notmatch '(?i)\\Windows\\System32\\(drivers\\)?[a-z0-9]+\.sys' } |
    Sort-Object Name | Select-Object -First 25 | ForEach-Object { "  {0,-26} {1}" -f $_.Name, $_.PathName }
"-- problem devices (yellow bang in Device Manager) --"
Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
    ForEach-Object { "  err={0}  {1}" -f $_.ConfigManagerErrorCode, $_.Name }

Section "INSTALLED_INVENTORY"
$uni = @()
foreach ($r in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
               'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
               'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
    $uni += Get-ItemProperty $r | Where-Object { $_.DisplayName -and -not $_.SystemComponent }
}
"desktop_apps={0}" -f ($uni | Select-Object -ExpandProperty DisplayName -Unique).Count
"store_apps={0}"   -f (Get-AppxPackage | Where-Object { -not $_.IsFramework }).Count

Section "END"
"scan complete - nothing was modified"
