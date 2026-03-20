#!/bin/bash

get_cpu_temp() {
  temps=()
  for i in /sys/class/hwmon/hwmon*/temp*_input; do
    dirname=$(dirname $i)
    if grep -q "coretemp" "$dirname/name" 2>/dev/null; then
      temp=$(($(cat "$i" 2>/dev/null) / 1000))
      temps+=("$temp")
    fi
  done

  if [ ${#temps[@]} -gt 0 ]; then
    printf '%s\n' "${temps[@]}" | awk '{sum+=$1} END {printf "%.0f", sum/NR}'
  else
    echo "0"
  fi
}

get_nvme_temp() {
  for i in /sys/class/hwmon/hwmon*/temp*_input; do
    dirname=$(dirname $i)
    if grep -q "nvme" "$dirname/name" 2>/dev/null; then
      echo $(($(cat "$i" 2>/dev/null) / 1000))
      return
    fi
  done
  echo "0"
}

get_mb_temp() {
  for i in /sys/class/hwmon/hwmon*/temp*_input; do
    dirname=$(dirname $i)
    if grep -q "acpitz" "$dirname/name" 2>/dev/null; then
      echo $(($(cat "$i" 2>/dev/null) / 1000))
      return
    fi
  done
  echo "0"
}

case $1 in
notify)
  cpu=$(get_cpu_temp)
  nvme=$(get_nvme_temp)
  mb=$(get_mb_temp)
  notify-send "Temperatures" \
    "<b>CPU:</b> ${cpu}°C\n<b>NVMe:</b> ${nvme}°C\n<b>MB:</b> ${mb}°C" \
    -u low -t 3000
  ;;
*)
  echo "%{T2}%{T-} $(get_cpu_temp)"
  ;;
esac
