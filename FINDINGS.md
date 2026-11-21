# Findings

All TCL power logic runs inside `system_server`, not in a separate app. Disabling Smart Manager (`com.tct.onetouchbooster`) does not stop it.

## Where the code lives

| File | Class | Role |
|---|---|---|
| `/system/framework/perf-services.jar` | `com.tcl.server.perf.pm.TclPerfManagerService` | `perf_manager` binder service, routes events to the modules below |
| | `com.tcl.server.power.scenario.SleepModeManager` | Sleep mode: force-stops, whitelist removal, restrictions |
| | `com.tcl.server.power.scenario.SleepModeMonitor` | Predicts sleep/wake times from screen-off history |
| | `com.tcl.server.perf.config.TclPowerConfig` | Reads feature flags from the `ConfigPerf` config |
| | `com.tcl.server.power.backgroundcontroller.BackgroundController` | Daytime background restriction ("Smart BG restrict") |
| | `com.tcl.server.power.abnormal.AbnormalService` | Force-stops apps flagged for abnormal power use |
| | `com.tcl.server.power.superpower.SuperPowerSaveManager` | Super power saving mode |
| `/system/framework/tcl-services.jar` | `com.android.server.am.TGuardAppTypeManager` | App category database (IM, game, browser, ...) |
| `/system/framework/services.jar` | `com.android.server.DeviceIdleController` | AOSP Doze, with TCL additions |
| `/system/priv-app/ConfigProvider` | `com.tcl.providers.config` | Feature config database (see below) |

## Sleep mode

`SleepModeMonitor` sends a "sleep start" event (5) when it predicts sleep and "sleep end" (6) on wake. `SleepModeManager.enterSleepSaveMode()` then:

1. Saves GPS/NFC/Wi-Fi/data state to `key_json_pre_phone_statue` and turns them off (Wi-Fi and data stay on if `tct_sleep_stay_conn_net_enable=1`).
2. Asks Smart Manager for a "one key clean".
3. If V2 is enabled:
   - `handleDeviceBgRestrictMapApps(true)`: removes "blacklisted" apps from the Doze user whitelist. The removed list is kept **only in memory**.
   - `clearBackgroundApps()`: force-stops background processes (importance > 350, plus some lower ones by category).
   - `restrictBackgroundApps()`: sets appop `RUN_ANY_IN_BACKGROUND` to `ignore` ("Restricted") and stores the UIDs in `sleep_bg_ignore`.

`exitSleepSaveMode()` reverses all of this.

**Exempt from force-stop** (`checkIgnore`): current keyboard, live wallpaper, apps with home-screen widgets, floating windows, apps playing audio, core system/Google apps. **The Doze whitelist is not checked.**

**"Blacklisted"** (`isBlackListApp`): TGuard category is browser, game, music, video, gallery, camera, shop, news, office, navigation, VPN, ebook and others, **or unknown (`-1`)**. Unknown means the package isn't in TCL's category database, which covers most apps outside the Play Store. Spared categories include IM, SMS, email, clock and launcher.

### Bugs

- **Enter ignores the user toggle, exit requires it.** Event 5 calls `enterSleepSaveMode()` without checking `tct_sleep_save_mode_enable`. Event 6 and the wake alarm only exit when it is `1`. With the toggle at `0`, sleep mode is entered once and never exited until reboot; the whitelist removals and restrictions stay in place for days.
- **Whitelist restore is lost on reboot.** The removed-apps list lives in memory. On shutdown the exit re-adds them, but `DeviceIdleController` writes `deviceidle.xml` 5 s after a change, so the restore often never reaches disk.
- **Charging short-circuits entry.** If the phone is plugged in at sleep start, `enterSleepSaveMode()` sets `isSleeping=true` and returns before doing anything. Until the next exit, later sleep events are ignored.

### TCL changes in `DeviceIdleController`

- `USER_APP_WHITELIST = {"com.tcl.fota.system", "com.android.phone"}`: re-added to the user whitelist at every boot and on install.
- Config writes are delayed 5 s (`writeConfigFileLocked`).

## Settings

All in `Settings.Secure` (`settings get|put secure <key>`). Default applies when the key is missing.

| Key | Default | Meaning |
|---|---|---|
| `tct_sleep_save_mode_enable` | 1 | Sleep power-save toggle. Only gates exit and alarms, see bugs above. Leave unset or `1`. |
| `tct_sleep_stay_conn_net_enable` | 1 | Keep Wi-Fi/data on during sleep mode |
| `tct_sleep_charge_mode_enable` | 0 | Smart charging (pause at 80% overnight) |
| `tct_sleep_mode` | – | Written by `SleepModeMonitor`: `1` sleeping, `2` awake. Not a switch. |
| `sleep_mode_on` | – | `1` while sleep mode is entered; triggers an exit at boot |
| `sleep_bg_ignore` | – | UIDs restricted by the last sleep entry |
| `key_json_pre_phone_statue` | – | Radio state saved on sleep entry |
| `feature_bg_restrict_enable` | 1 | `BackgroundController` master switch. It **does** respect the Doze whitelist. |

System properties (`system_prop`, need root to change):

| Property | Default | Meaning |
|---|---|---|
| `persist.sys.tct.sleep.mode.version` | 2 | `2` enables the V2 steps (whitelist removal, force-stop, restrict) |
| `persist.sys.tct.sleep.debugmode` | false | Shorter timers for testing |
| `persist.sys.sleep.extra.ctrl` | true | Also force-stops foreground services of some categories |

## Feature config (ConfigProvider)

`com.tcl.providers.config` stores 43 JSON "projects" (shared with TCL TVs, so many entries are TV-only).

- URI: `content://com.tcl.providers.config/<project>` (`all` lists everything)
- Exported with **no permission**: the ADB shell can read and write it.
- Rebuilt at every boot from `/vendor/etc/default_feature_config.json` and `/vendor/etc/product_dynamic_feature_config.json`. Cloud updates go through `/data/user_de/0/com.tcl.providers.config/files/setting_feature.json`.
- Consumers register a `ContentObserver`, so changes apply immediately. `dumpsys content` shows which projects are observed.

### `ConfigPerf` → `TclPowerConfig`

```json
"sleep_predication": {"enable": "true", "charging": "true", "power-save": "true", "power-save_V2": "true"}
```

| Flag | Effect when `false` |
|---|---|
| `enable` | Disables sleep prediction (and everything below) |
| `charging` | Disables smart charging |
| `power-save` | `enterSleepSaveMode()` returns immediately. **This is the fix.** |
| `power-save_V2` | Skips only the V2 steps |

Other sections: `power_abnormal` (`kill_enable`, `whiteAppList`), `smart_bg_restrict` (`restrictblacklist`), `superpowersave` (`disablelist`, `restrictlist`).

### Other projects worth knowing

| Project | Notes |
|---|---|
| `TGuardMemoryManager` | TCL memory killer. `KillEnable`, `PollingCleanIntervalMS=30000`, `ImportantAppList` (protected: WhatsApp, WeChat, Facebook, ...), `KillWhiteList` |
| `AppBootPolicy` | Auto-start / association-start control, `procWhiteList`, starts enforcing `powerOnCtlTime=60` s after boot |
| `IpelEngine` | UX/frame boosting. `benchmarkWhiteList` contains AnTuTu, Geekbench, PCMark, GFXBench, AndroBench |
| `freeze`, `TScene` | App freezer and game/navigation scenes, disabled |

## Hidden commands

All work from the ADB shell (UID 2000), so also through Shizuku.

```sh
# Sleep mode status: support flags, toggles, isFakeSleepMode, isSleeping
dumpsys perf_manager sleep_mode

# Fake sleep: 5 = start, 6 = end, time in ms. While isFakeSleepMode is true,
# real sleep events are ignored. Reset on reboot.
dumpsys perf_manager sleep_mode fake_sleep 5 <epoch_ms>
dumpsys perf_manager sleep_mode fake_sleep 6 <epoch_ms>

# Send a raw sleep event (5 start, 6 end) with a wake-up timestamp in seconds
dumpsys perf_manager sleep_mode debug 5 <epoch_s>

# Sleep prediction internals
dumpsys perf_manager sleep_mode monitor

# Other modules
dumpsys perf_manager background_controller info   # "debug" subcommands refuse UID 2000
dumpsys perf_manager abnormal_notification

# Feature config
cmd feature query all
cmd feature query ConfigPerf
cmd feature update ConfigPerf '<full json>' feature   # 4th arg is required, any value except "prop"

# Doze whitelist
dumpsys deviceidle whitelist            # lists system/user entries
dumpsys deviceidle whitelist +<pkg>     # add
dumpsys deviceidle whitelist -<pkg>     # remove
```

`content update --bind` can't write these configs: it splits the value on `:`.

Useful logcat tags: `SleepModeManager`, `SleepModeManager_V2`, `Power_SleepModeMonitor`, `PERF/TclPowerConfig`.

## Forcing a clean exit from sleep mode

If sleep mode was entered (`isSleeping: true`), this runs TCL's own exit, which restores the whitelist entries it removed, un-restricts apps and restores GPS/NFC:

```sh
settings put secure tct_sleep_save_mode_enable 1
dumpsys perf_manager sleep_mode debug 6 0                  # or, if isFakeSleepMode is true:
# dumpsys perf_manager sleep_mode fake_sleep 6 <now_ms>
settings put secure tct_sleep_save_mode_enable <previous value>
```

Force-stopped apps stay stopped until opened.

## OTA updates

Firmware updates may change any of the above. To freeze the firmware:

```sh
pm disable-user --user 0 com.tcl.fota.system   # TCL system updates
pm disable-user --user 0 com.tct.smart.aota    # TCL preinstalled-app updates
```

Re-enable with `pm enable <pkg>`. Google Play system updates are unaffected.
