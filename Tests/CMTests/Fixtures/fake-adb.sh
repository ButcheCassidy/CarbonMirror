#!/bin/sh
# Stand-in for adb in Linux tests: records every argv, answers like adb, and can simulate a crash.
printf '%s\n' "$*" >> "$HOME/fake-adb.log"
case "$1" in
  start-server|kill-server)
    exit 0
    ;;
  devices)
    printf 'List of devices attached\nSERIAL1                device usb:1-1 product:mustang model:Pixel_10_Pro_XL device:mustang transport_id:1\n'
    ;;
  track-devices)
    payload=$(printf 'SERIAL1\tdevice usb:1-1 product:mustang model:Pixel_10_Pro_XL device:mustang transport_id:1')
    printf '%04x%s' "${#payload}" "$payload"
    if [ -f "$HOME/crash-once" ]; then
      rm -f "$HOME/crash-once"
      exit 1
    fi
    exec sleep 60
    ;;
  -s)
    exit 0
    ;;
  *)
    exit 2
    ;;
esac
