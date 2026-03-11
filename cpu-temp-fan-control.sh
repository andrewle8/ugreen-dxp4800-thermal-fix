#!/bin/bash
# CPU-temp-based fan controller for UGREEN DXP4800+
# ACPI fans are binary (on/off), bound to board temp not CPU temp.
# This script monitors coretemp and toggles fans with a minimum-on
# duration to prevent rapid oscillation.

LOG=/var/log/cpu-fan-control.log
INTERVAL=5
THRESHOLD_ON=75
THRESHOLD_OFF=50
MIN_ON_SECS=120

CORETEMP_HWMON=""
for hwmon in /sys/class/hwmon/hwmon*; do
  if [ "$(cat "$hwmon/name" 2>/dev/null)" = "coretemp" ]; then
    CORETEMP_HWMON="$hwmon"
    break
  fi
done

if [ -z "$CORETEMP_HWMON" ]; then
  echo "$(date): ERROR - coretemp hwmon not found" >> "$LOG"
  exit 1
fi

FAN_DEVS=""
for dev in /sys/class/thermal/cooling_device*; do
  [ "$(cat "$dev/type" 2>/dev/null)" = "Fan" ] && FAN_DEVS="$FAN_DEVS $dev"
done

if [ -z "$FAN_DEVS" ]; then
  echo "$(date): ERROR - no fan cooling devices found" >> "$LOG"
  exit 1
fi

echo "$(date): Started. coretemp=$CORETEMP_HWMON fans=$FAN_DEVS thresholds=on>${THRESHOLD_ON} off<${THRESHOLD_OFF} min_on=${MIN_ON_SECS}s" >> "$LOG"

get_max_cpu_temp() {
  local max=0
  for f in "$CORETEMP_HWMON"/temp*_input; do
    [ -f "$f" ] || continue
    local t=$(cat "$f" 2>/dev/null)
    t=$((t / 1000))
    [ "$t" -gt "$max" ] && max=$t
  done
  echo "$max"
}

set_fans() {
  local state=$1
  for dev in $FAN_DEVS; do
    echo "$state" > "$dev/cur_state" 2>/dev/null
  done
}

FANS_ON=0
FAN_ON_SINCE=0

while true; do
  TEMP=$(get_max_cpu_temp)
  NOW=$(date +%s)

  if [ "$FANS_ON" -eq 0 ] && [ "$TEMP" -ge "$THRESHOLD_ON" ]; then
    set_fans 1
    FANS_ON=1
    FAN_ON_SINCE=$NOW
    echo "$(date): CPU=${TEMP}C >= ${THRESHOLD_ON}C -> fans ON" >> "$LOG"
  elif [ "$FANS_ON" -eq 1 ]; then
    ELAPSED=$(( NOW - FAN_ON_SINCE ))
    if [ "$TEMP" -le "$THRESHOLD_OFF" ] && [ "$ELAPSED" -ge "$MIN_ON_SECS" ]; then
      set_fans 0
      FANS_ON=0
      echo "$(date): CPU=${TEMP}C <= ${THRESHOLD_OFF}C (on for ${ELAPSED}s) -> fans OFF" >> "$LOG"
    fi
  fi

  sleep $INTERVAL
done
