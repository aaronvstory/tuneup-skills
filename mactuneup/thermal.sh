#!/bin/bash
# Read-only heat and throttle check. Prints KEY=VALUE lines, so nobody needs a screenshot.
#   bash thermal.sh
# No sudo. Temperatures and power need macmon on Apple silicon (brew install macmon).
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

kv() { printf '%s=%s\n' "$1" "$2"; }

# 1. Thermal pressure: built in. 0 nominal, 1 moderate, 2 heavy, 3 trapping, 4 sleeping.
level=$(notifyutil -g com.apple.system.thermalpressurelevel 2>/dev/null | awk '{print $2}')
kv THERMAL_PRESSURE_LEVEL "${level:-unknown}"

# 2. Intel Macs report a speed limit here. Apple silicon reports nothing, which is normal.
limit=$(pmset -g therm 2>/dev/null | awk -F= '/CPU_Speed_Limit/ {gsub(/ /,"",$2); print $2}')
[ -n "$limit" ] && kv CPU_SPEED_LIMIT_PCT "$limit"

# 3. Load: a busy Mac is warm for an honest reason.
kv LOAD_AVERAGE "$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | xargs)"
kv CPU_COUNT "$(sysctl -n hw.ncpu)"

# 4. Sensors. Show macmon's JSON as is, so a new macmon field is not lost.
cpu_temp=""; cpu_w=""
if command -v macmon >/dev/null 2>&1; then
  json=$(macmon pipe -s 1 -i 1500 2>/dev/null | head -1)
  if [ -n "$json" ]; then
    kv SENSORS OK
    cpu_temp=$(printf '%s' "$json" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["temp"]["cpu_temp_avg"])' 2>/dev/null)
    cpu_w=$(printf '%s' "$json" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["cpu_power"])' 2>/dev/null)
    [ -n "$cpu_temp" ] && kv CPU_TEMP_C "$cpu_temp"
    [ -n "$cpu_w" ] && kv CPU_WATTS "$cpu_w"
  else
    kv SENSORS MACMON-FAILED
  fi
else
  kv SENSORS 'NOT-INSTALLED (brew install macmon)'
fi

# Verdict. A symptom to verify, not a final diagnosis.
verdict=NO-SIGN-OF-HEAT-LIMIT
case "$level" in
  0|'') ;;
  1) verdict='MODERATE-PRESSURE (compare with load)' ;;
  *) verdict='THROTTLING (heavy pressure: compare with load, then check vents, fans, and dust)' ;;
esac
[ -z "$level" ] && verdict=PRESSURE-UNKNOWN
if [ -n "$limit" ] && [ "$limit" -lt 100 ] 2>/dev/null; then verdict="THROTTLING (speed limit $limit%)"; fi
kv THERMAL_VERDICT "$verdict"
