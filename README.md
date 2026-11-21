# TCL Android battery fixes

Notes from reverse-engineering TCL's power management, plus a no-root fix for its sleep mode.

Tested on a TCL 50 SE (T611B) running Android 14. Other recent TCL phones likely share the same framework code, but class names, keys and defaults may differ between models and firmware versions.

- **[sleep-guard/](sleep-guard/)**: script + Tasker/Shizuku setup that neutralizes TCL sleep mode.
- **[FINDINGS.md](FINDINGS.md)**: how TCL's power services work, their settings, configs and hidden commands.

## The problem

TCL runs its own power manager on top of Android. Its **sleep mode** activates when the phone predicts you are asleep and:

- force-stops background apps (they show `stopped=true`, kill subreason 21 `FORCE STOP`),
- removes apps from the battery-optimization whitelist ("Unrestricted" silently reverts to "Optimized"),
- sets some apps to "Restricted",
- turns off GPS and NFC.

It ignores Android's battery-optimization whitelist, and any app TCL can't categorize (e.g. most F-Droid apps) is treated as a target.

## The fix, in short

TCL's feature config is stored in an exported content provider that the ADB shell can write. Setting `sleep_predication.power-save` to `false` in the `ConfigPerf` project disables sleep mode entirely. The provider restores defaults at every boot, so the guard script re-applies it via Tasker + Shizuku. See [sleep-guard/](sleep-guard/).
