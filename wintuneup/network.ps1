#Requires -Version 5.1
<#
Read-only network analysis. Prints KEY=VALUE lines.
Sends 10 pings per target and downloads 25 MB and uploads 5 MB through Cloudflare's public speed test.
  -NoSpeed skips the transfers on a metered link.
#>
param([switch]$NoSpeed)
function Out-Kv($k, $v) { "{0}={1}" -f $k, $v }

function Ping-Stats($name, $target) {
    $ping = New-Object System.Net.NetworkInformation.Ping
    $t = @(); $lost = 0
    1..10 | ForEach-Object {
        try { $r = $ping.Send($target, 1500); if ($r.Status -eq 'Success') { $t += [int]$r.RoundtripTime } else { $lost++ } } catch { $lost++ }
        Start-Sleep -Milliseconds 150
    }
    if ($t.Count) {
        $m = $t | Measure-Object -Average -Minimum -Maximum
        Out-Kv "PING_$name" ('avg {0:N0} ms, min {1}, max {2}, lost {3}/10' -f $m.Average, $m.Minimum, $m.Maximum, $lost)
    } else { Out-Kv "PING_$name" 'lost 10/10' }
}

$route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
$gw = $route.NextHop
if ($route) { Out-Kv 'ACTIVE_ADAPTER' (Get-NetAdapter -InterfaceIndex $route.InterfaceIndex).InterfaceDescription }
Out-Kv 'GATEWAY' $gw

$w = netsh wlan show interfaces 2>$null
if ($w) {
    foreach ($f in 'Band', 'Radio type', 'Channel', 'Signal', 'Receive rate \(Mbps\)', 'Transmit rate \(Mbps\)') {
        $l = $w | Where-Object { $_ -match "^\s*$f\s*:" } | Select-Object -First 1
        if ($l) { Out-Kv ('WIFI_' + (($f -replace '\\\(Mbps\\\)', 'Mbps') -replace '[^A-Za-z]', '').ToUpper()) (($l -split ':', 2)[1].Trim()) }
    }
}

if ($gw) { Ping-Stats 'GATEWAY' $gw }
Ping-Stats 'INTERNET' '1.1.1.1'

# First hops: a far-slow hop 2 behind a fast hop 1 points to a tunnel on the router.
$hops = tracert -d -h 3 -w 800 1.1.1.1 2>$null | Where-Object { $_ -match '^\s*\d+\s' } | ForEach-Object { ($_ -replace '\s+', ' ').Trim() }
$i = 0; foreach ($h in $hops) { $i++; Out-Kv "HOP_$i" $h }

# DNS timing with a random name, so a cached answer cannot hide a slow resolver.
$sw = [Diagnostics.Stopwatch]::StartNew()
try { [void][Net.Dns]::GetHostAddresses("t$(Get-Random).example.com") } catch {}
Out-Kv 'DNS_MS' $sw.ElapsedMilliseconds
Out-Kv 'DNS_SERVERS' ((Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object InterfaceIndex -eq $route.InterfaceIndex).ServerAddresses -join ', ')

$v = @(foreach ($n in 'tailscaled','mullvad-daemon','warp-svc','WindscribeService','openvpn','wireguard','nordvpn','expressvpn','ZeroTier One') { if (Get-Process $n -ErrorAction SilentlyContinue) { $n } })
Out-Kv 'VPN_PROCS' ($v -join ', ')
$rem = @(foreach ($n in 'AnyDesk','parsecd','remoting_host','TeamViewer_Service','winvnc','tvnserver','sshd') { if (Get-Process $n -ErrorAction SilentlyContinue) { $n } })
Out-Kv 'REMOTE_ACCESS_PROCS' ($rem -join ', ')
Out-Kv 'LISTENING_PUBLIC_PORTS' (@(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -in '0.0.0.0', '::' } | ForEach-Object LocalPort | Sort-Object -Unique) -join ',')

try { $ip = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -TimeoutSec 8; Out-Kv 'PUBLIC_EXIT' ("$($ip.ip) $($ip.city) $($ip.org)") } catch { Out-Kv 'PUBLIC_EXIT' 'unknown' }

if (-not $NoSpeed) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $c = New-Object Net.WebClient; $sw.Restart()
        $b = $c.DownloadData('https://speed.cloudflare.com/__down?bytes=25000000')
        Out-Kv 'DOWNLOAD_MBPS' ('{0:N0}' -f ($b.Length * 8 / 1e6 / $sw.Elapsed.TotalSeconds))
        $u = New-Object byte[] 5000000; $sw.Restart()
        [void]$c.UploadData('https://speed.cloudflare.com/__up', 'POST', $u)
        Out-Kv 'UPLOAD_MBPS' ('{0:N0}' -f ($u.Length * 8 / 1e6 / $sw.Elapsed.TotalSeconds))
    } catch { Out-Kv 'SPEED_TEST' "failed: $($_.Exception.Message)" }
}
