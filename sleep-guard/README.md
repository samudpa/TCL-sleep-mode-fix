# Sleep guard

Stops TCL sleep mode from force-stopping apps, removing them from the battery-optimization whitelist and restricting them. No root needed. Background in [FINDINGS.md](../FINDINGS.md).

## What the script does

1. **Disables sleep mode** by setting `ConfigPerf` → `sleep_predication.power-save` to `false`.
2. **Sets the fake-sleep flag** as a second layer: TCL then ignores real sleep events.
3. **Repairs** a sleep entry that already happened (whitelist, restricted apps, GPS/NFC) by triggering TCL's own exit.
4. **Snapshots your battery-optimization whitelist** to `/sdcard/tcl_guard/whitelist.txt` and restores it after a reboot or a sleep entry.

1 and 2 are reset at every reboot, so the script has to run again after each boot. Tasker handles that.

## Requirements

- [Shizuku](https://shizuku.rikka.app/)
- [Tasker](https://tasker.joaoapps.com/) with Shizuku support (Run Shell → *Use Shizuku*, *Shizuku Available* state)

## Install

1. **Shizuku.** Start it with wireless debugging (see the Shizuku app). Enable *Start on boot* if your version offers it.
2. **Tasker.** Open it once, then allow it in Shizuku when asked (or in Shizuku → *Authorized apps*).
3. **Battery.** Set Tasker and Shizuku to *Unrestricted* (App info → Battery).
4. **Script.** Copy `tcl_sleep_guard.sh` to the root of internal storage, so it ends up at `/sdcard/tcl_sleep_guard.sh`.
5. **Task** `TCL Guard`:
   1. *Task → Wait*: 30 seconds
   2. *Code → Run Shell*
      - Command: `sh /sdcard/tcl_sleep_guard.sh`
      - Use Shizuku: on
      - Store Output In: `%guardout`
   3. Optional while testing: *Alert → Flash* `%guardout`
6. **Profiles:**

   | Profile | Context | Task |
   |---|---|---|
   | On Shizuku | State → *Shizuku Available* | `TCL Guard` |
   | Periodic | Time 00:00–23:59, repeat every 30 min, **plus** State → *Shizuku Available* | `TCL Guard` |

   The first covers boot and Shizuku restarts. The second re-applies the config if TCL's cloud sync resets it, and keeps the whitelist snapshot current.

## Check it

After a reboot, once the task has run:

```sh
dumpsys perf_manager sleep_mode | head -4
```

Expected: `isSleepPowerSaveModeSupport:false`, `isFakeSleepMode:true`, `isSleeping: false`.

Script output lines:

| Line | Meaning |
|---|---|
| `config: sleep power-save disabled` / `already disabled` | OK |
| `config: key not found` | Firmware changed, the fix needs updating |
| `recovery: sleep mode exited` | A sleep entry happened before the script ran and was undone |
| `whitelist: snapshot saved` | Normal run, current whitelist recorded |
| `whitelist: restored from snapshot` | First run after a boot (or after a sleep entry), whitelist restored |

## Customizing

`PKGS` lists apps that are always re-added to the whitelist. By default: Tasker, Shizuku, Termux. Add your own critical apps there. Every other whitelisted app is covered by the snapshot.

To remove an app from the whitelist for good: remove it in Android settings, then let the script run once (not the first run after a reboot, which restores instead of saving).

## Limitations

- **Shizuku needs Wi-Fi to start after a reboot.** Until the script runs, sleep mode can trigger once. Plugging in the charger before going to bed avoids it (TCL skips sleep mode while charging). The next run repairs the whitelist, restrictions and GPS/NFC, but force-stopped apps stay stopped until opened.
- A firmware update can move or rename any of this. Consider disabling OTA updates (see [FINDINGS.md](../FINDINGS.md#ota-updates)).

## Undo

Delete the Tasker profiles and reboot. The config and fake-sleep flag reset at boot. Remove `/sdcard/tcl_guard/` if you like.
