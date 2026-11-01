#!/bin/bash
# Read-only network analysis. Prints KEY=VALUE lines. No sudo.
# Uses macOS networkQuality for speed. Pass --no-speed to skip it on a metered link.
kv() { printf '%s=%s\n' "$1" "$2"; }
ping_stats() {
  local out; out=$(ping -c 10 -i 0.2 -t 8 "$2" 2>/dev/null)
  kv "PING_$1" "$(printf '%s\n' "$out" | tail -2 | tr '\n' ' ' | sed 's/---[^-]*---//')"
}
iface=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
gw=$(route -n get default 2>/dev/null | awk '/gateway:/ {print $2}')
kv ACTIVE_INTERFACE "$iface"
kv GATEWAY "$gw"
kv INTERFACE_MTU "$(ifconfig "$iface" 2>/dev/null | awk '/mtu/ {print $NF; exit}')"
kv WIFI "$(system_profiler SPAirPortDataType 2>/dev/null | awk '/Current Network Information:/{f=1;next} f&&/PHY Mode|Channel|Signal|Transmit Rate/{gsub(/^ +/,""); printf "%s; ",$0} /Other Local/{f=0}')"
[ -n "$gw" ] && ping_stats GATEWAY "$gw"
ping_stats INTERNET 1.1.1.1
# A far-slow hop 2 behind a fast hop 1 points to a tunnel on the router.
traceroute -n -m 3 -w 1 1.1.1.1 2>/dev/null | awk '{print "HOP_" $1 "=" $0}'
start=$(/usr/bin/python3 -c 'import time;print(time.time())')
dscacheutil -q host -a name "t$RANDOM$RANDOM.example.com" >/dev/null 2>&1
kv DNS_MS "$(/usr/bin/python3 -c "import time;print(int((time.time()-$start)*1000))")"
kv DNS_SERVERS "$(scutil --dns 2>/dev/null | awk '/nameserver\[0\]/ {print $3}' | sort -u | tr '\n' ' ')"
vpn=""; for p in tailscaled mullvad-daemon warp-svc openvpn wireguard-go nordvpnd zerotier-one; do pgrep -xq "$p" && vpn="$vpn $p"; done
kv VPN_PROCS "$vpn"
rem=""; for p in sshd AnyDesk parsecd remoting_me2me_host TeamViewer screensharingd; do pgrep -xq "$p" && rem="$rem $p"; done
kv REMOTE_ACCESS_PROCS "$rem"
kv LISTENING_PUBLIC_PORTS "$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk '$9 ~ /^\*:/ {sub(/^\*:/,"",$9); print $9}' | sort -un | tr '\n' ',')"
kv PUBLIC_EXIT "$(curl -s -m 8 https://ipinfo.io/json | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("ip"),d.get("city"),d.get("org"))' 2>/dev/null)"
if [ "$1" != "--no-speed" ] && command -v networkQuality >/dev/null; then
  networkQuality -c -M 15 2>/dev/null | /usr/bin/python3 -c 'import json,sys
d=json.load(sys.stdin)
print("DOWNLOAD_MBPS=%d"%(d["dl_throughput"]/1e6)); print("UPLOAD_MBPS=%d"%(d["ul_throughput"]/1e6)); print("RESPONSIVENESS_RPM=%d"%d.get("responsiveness",0))'
fi
