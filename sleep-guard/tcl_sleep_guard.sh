#!/system/bin/sh
# TCL sleep guard. Run as the ADB shell user (Shizuku, rish or adb shell):
#   sh /sdcard/tcl_sleep_guard.sh
# Safe to run any time. Must run again after every reboot.
#
# 0) Recovery: if sleep mode was already entered, force TCL's own exit. This restores removed
#    whitelist entries, un-restricts apps and restores GPS/NFC.
# 1) Sets ConfigPerf sleep_predication.power-save=false, so sleep mode never runs.
#    ConfigProvider restores the default at boot, hence the re-run.
# 2) Sets the in-memory "fake sleep" flag, so real sleep events are ignored (second layer).
# 3) Keeps a snapshot of the battery-optimization whitelist and restores it after a reboot
#    or a sleep entry. Apps in PKGS are always re-added.

PKGS="net.dinglisch.android.taskerm moe.shizuku.privileged.api com.termux"
DIR=/sdcard/tcl_guard
URI="content://com.tcl.providers.config/ConfigPerf"
KEY=tct_sleep_save_mode_enable

sm() { dumpsys perf_manager sleep_mode; }
wait_for() { i=0; while [ $i -lt 10 ]; do sm | grep -q "$1" && return 0; sleep 1; i=$((i+1)); done; return 1; }

mkdir -p "$DIR"
BOOT=$(cat /proc/sys/kernel/random/boot_id)
LASTBOOT=$(cat "$DIR/boot_id" 2>/dev/null)
WAS_SLEEPING=$(sm | grep -c "isSleeping: true")

# 0) Recovery
if [ "$WAS_SLEEPING" -gt 0 ]; then
  ORIG=$(settings get secure $KEY)
  settings put secure $KEY 1
  if wait_for "isSleepPowerSaveEnable:true"; then
    if sm | grep -q "isFakeSleepMode:true"; then
      dumpsys perf_manager sleep_mode fake_sleep 6 "$(date +%s)000"
    else
      dumpsys perf_manager sleep_mode debug 6 0
    fi
    if wait_for "isSleeping: false"; then echo "recovery: sleep mode exited"
    else echo "recovery: exit did not happen"; fi
  else
    echo "recovery: setting not picked up"
  fi
  if [ "$ORIG" = "null" ]; then settings delete secure $KEY >/dev/null; else settings put secure $KEY "$ORIG"; fi
fi

# 1) Config switch
CUR=$(content query --uri "$URI" --projection config_content | sed 's/^Row: 0 config_content=//')
case "$CUR" in
  *'"power-save":"true"'*)
    NEW=$(printf '%s' "$CUR" | sed 's/"power-save":"true"/"power-save":"false"/')
    cmd feature update ConfigPerf "$NEW" feature >/dev/null 2>&1
    CHECK=$(content query --uri "$URI" --projection config_content | sed 's/^Row: 0 config_content=//')
    if [ "$CHECK" = "$NEW" ]; then echo "config: sleep power-save disabled"; else echo "config: write failed"; fi
    ;;
  *'"power-save":"false"'*) echo "config: already disabled" ;;
  *) echo "config: key not found (firmware changed?)" ;;
esac

# 2) Fake-sleep latch (2100-01-01, never fires)
if sm | grep -q "isFakeSleepMode:false"; then
  dumpsys perf_manager sleep_mode fake_sleep 5 4102444800000
  echo "latch: set"
else
  echo "latch: already set"
fi

# 3) Whitelist snapshot
if [ -s "$DIR/whitelist.txt" ] && { [ "$BOOT" != "$LASTBOOT" ] || [ "$WAS_SLEEPING" -gt 0 ]; }; then
  for p in $PKGS $(cat "$DIR/whitelist.txt"); do
    dumpsys deviceidle whitelist +"$p" >/dev/null 2>&1
  done
  echo "whitelist: restored from snapshot ($(wc -l < "$DIR/whitelist.txt") apps)"
else
  for p in $PKGS; do
    dumpsys deviceidle whitelist +"$p" >/dev/null 2>&1
  done
  dumpsys deviceidle whitelist | sed -n 's/^user,\([^,]*\),.*/\1/p' > "$DIR/whitelist.txt"
  echo "whitelist: snapshot saved ($(wc -l < "$DIR/whitelist.txt") apps)"
fi
echo "$BOOT" > "$DIR/boot_id"

sm | head -4
