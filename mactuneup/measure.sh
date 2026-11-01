#!/bin/bash
# mactuneup — measure.sh
#
# ONE state snapshot, identical every time, so before/after is comparable.
# Read-only. No sudo. Takes ~35s (it settles first — see SKILL.md "Measuring").
#
#   bash ~/.claude/skills/mactuneup/measure.sh            # settle 30s, then measure
#   bash ~/.claude/skills/mactuneup/measure.sh --now      # skip settle (baseline only)
#   bash ~/.claude/skills/mactuneup/measure.sh --inventory  # + About This Mac counts
#
# Emits KEY=VALUE lines so successive runs diff cleanly.

SETTLE=30
INVENTORY=0
for a in "$@"; do
  case "$a" in
    --now)       SETTLE=0 ;;
    --inventory) INVENTORY=1 ;;
  esac
done

[ "$SETTLE" -gt 0 ] && sleep "$SETTLE"

# top -l 3, discard sample 1: the first is a cumulative average since boot,
# not an instantaneous reading. This is the whole reason naive measurement lies.
TOP=$(top -l 3 -n 0 -s 2 2>/dev/null)
CPU=$(echo "$TOP"     | grep '^CPU usage'  | tail -1)
MEM=$(echo "$TOP"     | grep '^PhysMem'    | tail -1)

echo "TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')"
echo "UPTIME=$(uptime | sed 's/.*up //;s/,.*users.*//' | xargs)"
echo "LOAD_1=$(uptime | sed 's/.*load averages: //' | awk '{print $1}')"
echo "CORES=$(sysctl -n hw.ncpu)"
echo "CPU_IDLE=$(echo "$CPU" | grep -oE '[0-9.]+% idle' | tr -d ' %idle')"
echo "CPU_SYS=$(echo  "$CPU" | grep -oE '[0-9.]+% sys'  | tr -d ' %sy')"

echo "MEM_WIRED_MB=$(echo "$MEM"      | grep -oE '[0-9]+M wired'      | tr -dc 0-9)"
echo "MEM_COMPRESSOR_MB=$(echo "$MEM" | grep -oE '[0-9]+M compressor' | tr -dc 0-9)"
echo "MEM_UNUSED_MB=$(echo "$MEM"     | grep -oE '[0-9]+M unused'     | tr -dc 0-9)"
echo "MEM_RAW=$MEM"

SW=$(sysctl -n vm.swapusage)
echo "SWAP_TOTAL=$(echo "$SW" | awk '{print $3}')"
echo "SWAP_USED=$(echo  "$SW" | awk '{print $6}')"

echo "PROCESSES=$(ps ax | wc -l | tr -d ' ')"
echo "DISK_FREE=$(df -h /System/Volumes/Data | tail -1 | awk '{print $4}')"
echo "DISK_PCT=$(df -h  /System/Volumes/Data | tail -1 | awk '{print $5}')"
echo "SNAPSHOTS=$(tmutil listlocalsnapshots / 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
# Container free space vs df: they disagree whenever an APFS snapshot pins deleted
# files. Reporting df alone makes a real cleanup look like a no-op (or a regression).
# PURGEABLE_GB is roughly what thinning snapshots would hand back.
_cfree=$(diskutil info / 2>/dev/null | awk -F'[()]' '/Container Free Space/{print $2}' | awk '{print $1}')
_dfree=$(df -k /System/Volumes/Data 2>/dev/null | tail -1 | awk '{print $4*1024}')
echo "CONTAINER_FREE_GB=$(awk -v b="${_cfree:-0}" 'BEGIN{printf "%.1f", b/1e9}')"
echo "PURGEABLE_GB=$(awk -v c="${_cfree:-0}" -v d="${_dfree:-0}" 'BEGIN{g=(c-d)/1e9; if(g<0)g=0; printf "%.1f", g}')"
echo "UTUN=$(ifconfig | grep -c '^utun')"

# top CPU + top RAM, one line each, for eyeballing what moved
echo "TOP_CPU=$(ps -axo pcpu,comm -r | sed -n 2p | awk '{printf "%s %s", $1, $2}' | sed 's|.*/||')"
echo "TOP_RSS=$(ps -axo rss,comm  -m | sed -n 2p | awk '{printf "%dMB %s", $1/1024, $2}' | sed 's|.*/||')"

if [ "$INVENTORY" = "1" ]; then
  echo "APPS=$(ls /Applications 2>/dev/null | wc -l | tr -d ' ')"
  echo "BREW=$(ls /opt/homebrew/Cellar 2>/dev/null | wc -l | tr -d ' ')"
  echo "LOGIN_ITEMS=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | tr ',' '\n' | wc -l | tr -d ' ')"
  echo "LAUNCH_JOBS=$(( $(ls /Library/LaunchAgents 2>/dev/null | wc -l) + $(ls /Library/LaunchDaemons 2>/dev/null | wc -l) + $(ls ~/Library/LaunchAgents 2>/dev/null | wc -l) ))"
  echo "KEXTS=$(kmutil showloaded --list-only 2>/dev/null | wc -l | tr -d ' ')"
  echo "MCP_DESKTOP=$(python3 -c "import json,os;p=os.path.expanduser('~/Library/Application Support/Claude/claude_desktop_config.json');print(len(json.load(open(p)).get('mcpServers',{})))" 2>/dev/null || echo n/a)"
  echo "MCP_CODE=$(python3 -c "import json,os;print(len(json.load(open(os.path.expanduser('~/.claude.json'))).get('mcpServers',{})))" 2>/dev/null || echo n/a)"
  echo "IP=$(ipconfig getifaddr en0 2>/dev/null)"
  echo "VPNS=$(for n in tailscaled mullvad-daemon zerotier-one remoting_me2me; do pgrep -f "$n" >/dev/null && echo -n "$n "; done)"
fi
