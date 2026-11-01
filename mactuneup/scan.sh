#!/bin/bash
# mactuneup scan — READ ONLY. Changes nothing. No sudo required.
# Emits section-delimited findings for Claude to interpret.
export LC_ALL=C
H() { printf '\n===== %s =====\n' "$1"; }

H "IDENTITY"
sysctl -n machdep.cpu.brand_string 2>/dev/null
sw_vers 2>/dev/null
system_profiler SPHardwareDataType 2>/dev/null | grep -E "Model Name|Model Identifier|Total Number of Cores|Memory:"
uptime

H "THERMAL"
bash "$(dirname "$0")/thermal.sh" 2>&1

H "LOAD_VS_CORES"
CORES=$(sysctl -n hw.ncpu)
LOAD=$(uptime | sed 's/.*load averages*: //' | awk '{print $1}')
echo "cores=$CORES load1=$LOAD"
awk -v l="$LOAD" -v c="$CORES" 'BEGIN{r=l/c; printf "ratio=%.2f %s\n", r, (r>2?"OVERSUBSCRIBED":(r>1?"busy":"ok"))}'

H "MEMORY_SWAP"
sysctl vm.swapusage
echo "pageouts: $(sysctl -n vm.stats.vm.v_swapout 2>/dev/null || vm_stat | awk '/Pageouts/{print $NF}')"
memory_pressure 2>/dev/null | tail -2
echo "process count: $(ps ax | wc -l | tr -d ' ')"

H "TOP_CPU"
ps -Ao pcpu,pmem,rss,etime,comm -r 2>/dev/null | head -16

H "DISK"
df -h /System/Volumes/Data 2>/dev/null | tail -1
echo "-- local APFS snapshots (hold deleted files) --"
tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple" | sed 's/^/count: /'
echo "-- largest dirs in home --"
du -sh ~/Downloads ~/Library/Caches ~/Library/Containers ~/Movies ~/Documents 2>/dev/null | sort -rh
echo "-- Spotlight index size --"
du -sh ~/Library/Metadata/CoreSpotlight 2>/dev/null

H "AUDIO_HAL"
# Every driver here is loaded in-process by coreaudiod. Many = pegged CPU.
echo "coreaudiod CPU: $(ps -Ao pcpu,comm -r | awk '/coreaudiod/{print $1; exit}')"
echo "HAL drivers installed:"
ls /Library/Audio/Plug-Ins/HAL/ 2>/dev/null | sed 's/^/  /'
echo "count: $(ls /Library/Audio/Plug-Ins/HAL/ 2>/dev/null | wc -l | tr -d ' ')"

H "ORPHANED_LAUNCHD"
# Leftovers of uninstalled apps that still run at every boot. Highest-value finding.
#
# Two tiers, because one check is not enough:
#   ORPHAN  - a referenced filesystem path is gone. Definite.
#   REVIEW  - the job only invokes a system interpreter (osascript/sh/python), so
#             nothing is verifiably missing even when the owning app is long gone.
#             This is exactly where uninstalled-app cruft hides (Cocktail's jobs all
#             pointed at /usr/bin/osascript). Claude must judge these by vendor.
for d in ${LAUNCHD_DIRS:-/Library/LaunchAgents /Library/LaunchDaemons ~/Library/LaunchAgents}; do
  for f in "$d"/*.plist; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    case "$base" in com.apple.*) continue;; esac

    # Collect every argument that looks like an absolute path.
    #
    # PlistBuddy prints one array element per line, indented, e.g.
    #     Array {
    #         /Applications/Utilities/Adobe Creative Cloud/ACC/Creative Cloud
    #         --showwindow=false
    #     }
    # Paths routinely contain spaces, so parse LINE BY LINE and only trim the
    # surrounding indentation. Never tokenise on whitespace — doing that reported
    # 11 healthy Adobe/GPGTools/Logitech jobs as orphans on a 2026-08-02 run.
    args=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments" "$f" 2>/dev/null \
             | sed -e '1{/^Array {/d;}' -e '${/^}/d;}' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    prog=$(/usr/libexec/PlistBuddy -c "Print :Program" "$f" 2>/dev/null)
    [ -n "$prog" ] && args=$(printf '%s\n%s' "$prog" "$args")

    missing=""; concrete=0
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      case "$p" in
        /usr/bin/*|/bin/*|/usr/sbin/*|/sbin/*|/usr/libexec/*) continue;;  # system interpreters
        *\**|*=*) continue;;   # glob/flag values, not real paths
        /*) ;;                 # absolute path — check it
        *)  continue;;         # flags and bare words
      esac
      concrete=1
      # newline-delimited: paths contain spaces
      [ -e "$p" ] || missing="$missing$p"$'\n'
    done <<< "$args"

    if [ -n "$missing" ]; then
      echo "ORPHAN  $base"
      printf '%s' "$missing" | while IFS= read -r m; do
        [ -n "$m" ] && echo "        missing: $m"
      done
    elif [ "$concrete" -eq 0 ]; then
      echo "REVIEW  $base  (runs a system interpreter only — verify the vendor app still exists)"
      /usr/libexec/PlistBuddy -c "Print :ProgramArguments" "$f" 2>/dev/null | tr -d '\n' | sed 's/  */ /g;s/^/        args: /' ; echo
    fi
  done
done
echo "(no ORPHAN/REVIEW lines above = clean)"

H "THIRD_PARTY_LAUNCHD"
echo "-- /Library/LaunchDaemons --"; ls /Library/LaunchDaemons/ 2>/dev/null | grep -v "^com.apple" | sed 's/^/  /'
echo "-- /Library/LaunchAgents --"; ls /Library/LaunchAgents/ 2>/dev/null | grep -v "^com.apple" | sed 's/^/  /'
echo "-- ~/Library/LaunchAgents --"; ls ~/Library/LaunchAgents/ 2>/dev/null | sed 's/^/  /'

H "LOGIN_ITEMS"
osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null

H "NETWORK_TUNABLES"
# Compare against macOS defaults. "Optimizer" apps love to wreck these.
check() { v=$(sysctl -n "$1" 2>/dev/null); [ "$v" = "$2" ] && echo "  ok   $1 = $v" || echo "  DEVIATES  $1 = $v  (macOS default: $2)"; }
check net.inet.tcp.mssdflt 1460
check net.inet.tcp.win_scale_factor 4
check net.inet.tcp.delayed_ack 3
check net.inet.tcp.sendspace 131072
check net.inet.tcp.recvspace 131072
echo "-- persistent overrides --"
cat /etc/sysctl.conf 2>/dev/null || echo "  /etc/sysctl.conf: none (good)"

H "NETWORK_STATE"
echo "-- default route --"; route -n get default 2>/dev/null | grep -E "gateway|interface"
echo "-- DNS servers --"; scutil --dns 2>/dev/null | awk '/^resolver #1$/,/^$/' | grep -E "nameserver|search domain"
echo "-- resolv.conf --"; grep -v "^#" /etc/resolv.conf 2>/dev/null
echo "-- VPN tunnels (each = one more stack to traverse) --"
echo "utun count: $(ifconfig 2>/dev/null | grep -c '^utun')"
for p in tailscaled mullvad zerotier openvpn wireguard chromoting nordvpn expressvpn; do
  pgrep -x "$p" >/dev/null 2>&1 && echo "  running: $p"
  pgrep -f "$p" >/dev/null 2>&1 && ! pgrep -x "$p" >/dev/null 2>&1 && echo "  running: $p (matched by cmdline)"
done

H "DNS_HEALTH"
# Cache-aware + load-aware. Random names defeat the cache; varying the timeout
# separates a genuinely bad resolver from a CPU-starved client.
GW=$(route -n get default 2>/dev/null | awk '/gateway/{print $2}')
for t in 1 5; do
  f=0; for i in $(seq 1 15); do
    dig +time=$t +tries=1 @"${GW:-1.1.1.1}" "q$t-$i-$RANDOM.example.com" +short >/dev/null 2>&1 || f=$((f+1))
  done
  echo "gateway($GW) @${t}s timeout: $f/15 failed"
done
f=0; for i in $(seq 1 15); do
  dig +time=5 +tries=1 @1.1.1.1 "r$i-$RANDOM.example.com" +short >/dev/null 2>&1 || f=$((f+1))
done
echo "cloudflare @5s timeout: $f/15 failed"
echo "INTERPRET: failures that shrink as timeout grows = this Mac is starved, NOT the resolver."

H "TUNNEL_MTU"
# A VPN on the ROUTER is invisible from here except by its fingerprint: hop 1 is
# local-fast, hop 2 is far-slow. If the tunnel's MTU is smaller than this Mac's,
# large uploads die while downloads and browsing look perfectly fine. Windows
# machines on the same LAN hide the problem — they do PMTU black-hole detection
# and back off automatically. macOS does not.
echo "en0 MTU: $(ifconfig en0 2>/dev/null | awk '/mtu/{print $NF}')"
echo "-- first two hops (hop1 fast + hop2 slow = tunnel on the router) --"
traceroute -n -w 1 -q 1 -m 2 1.1.1.1 2>&1 | tail -2
echo "-- public IP / is it a datacenter? --"
curl -s -m 8 https://ipinfo.io/json 2>/dev/null | grep -E '"(ip|city|org)"' | sed 's/^/  /'
echo "-- large POST vs GET (the tell) --"
TMP=$(mktemp); dd if=/dev/urandom of="$TMP" bs=1024 count=1024 2>/dev/null
printf "  GET  1MB down: "; curl -sk -m 30 -o /dev/null "https://speed.cloudflare.com/__down?bytes=1000000" 2>/dev/null && echo OK || echo FAIL
printf "  POST 1MB up:   "; curl -sk -m 30 -o /dev/null -X POST --data-binary "@$TMP" "https://speed.cloudflare.com/__up" 2>/dev/null && echo OK || echo "RESET  <-- lower en0 MTU (try 1280); real fix is MSS clamping on the router"
rm -f "$TMP"

H "KEXTS_DEXTS"
kmutil showloaded --list-only 2>/dev/null | grep -vi "com.apple" | sed 's/^/  /' | head -20

H "END"
echo "scan complete — nothing was modified"
