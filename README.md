# Standable FBE Linux Patch (Unofficial)

> **You are on the `testing/rc` branch.** This is where all the new work
> lives. `main` is older and unmaintained - don't use it.
> [Browse `testing/rc`](https://github.com/meeyao/standable-linux-port/tree/testing/rc).
> Recent additions here (not on `main`):
> - [Desktop GUI window while SteamVR runs](https://github.com/meeyao/standable-linux-port/blob/testing/rc/templates/standable_launch_hook.sh.in) - launch hook runs the game in host context
> - [Runtime Proton switching](https://github.com/meeyao/standable-linux-port/blob/testing/rc/templates/proton_resolve.sh.in) - pick whatever Proton Steam forces, no reinstall
> - [Stale-process cleanup](https://github.com/meeyao/standable-linux-port/blob/testing/rc/install.sh) - clears leftover wineservers that caused the ~20 s Safe-Mode crash
> - [Manual install guide](https://github.com/meeyao/standable-linux-port/blob/testing/rc/MANUAL.md) and `--dry-run` for doing it by hand
>
> Note: some code here was written with the help of an LLM. It's been
> reviewed, but it's worth a skim before you rely on it - especially anything
> that kills processes or edits config files.

Runs Standable Full Body Estimation on Linux using the game's own Windows
binaries: driver, GUI window, realtime settings, T-pose calibration.
The game's own files stay untouched: the patch only adds helper files next to
them (a few in `bin/linux64/`) and places `steam_api64.dll` beside the
Windows driver in `bin/win64/`. No game file is overwritten or removed.

Based on [Ignition](https://github.com/BnuuySolutions/Ignition) by
Bnuuy Solutions (MIT). It provides the SteamVR-Proton bridge used here;
see `vendor/IGNITION-LICENSE`. This project is licensed under
[MIT](LICENSE). Prefer not to use the prebuilt binaries in `vendor/`?
[MANUAL.md](MANUAL.md) covers hash verification, substituting the
official upstream release, and building from source.

## Install

Requires Linux with a native (non-Flatpak) Steam install:

- **Steam** and **SteamVR** installed
- Standable Full Body Estimation installed (AppId **2370570**)
- A Proton build. `proton-cachyos-slr` and `DW-Proton` are verified end to
  end; Proton-GE, Experimental, and Proton 10 also work.

```sh
git clone -b testing/rc https://github.com/meeyao/standable-linux-port.git
cd standable-linux-port
./install.sh
```

(`testing/rc` is the actively-maintained branch. `main` is older/stable and
won't have the recent fixes - use `testing/rc` unless you specifically want
the older stable line.)

Then launch it through Steam as you would any other title. Start **SteamVR**,
then click **Play** on Standable.

To get the settings window on your desktop (instead of only in VR), set the
launch hook as the game's Launch Options - right-click **Standable** in Steam
→ **Properties** → **Launch Options**, set:
```
bash ~/bin/standable_launch_hook.sh %command%
```
The hook runs the game in host context so the desktop window renders while
SteamVR runs, and keeps the game and driver on the same Proton/prefix. Without
it, Steam launches the game as a VR overlay and there's no desktop window.

The game can be on any Steam library drive. The installer finds it.

Don't want to run the installer? [MANUAL.md](MANUAL.md) walks through the
same steps by hand, and `./install.sh --dry-run` prints every command with
your real paths.

## Compatibility

- Tested with **Steam Link** (on-PC and local network).
- **WiVRN** does not work with this patch.
- **ALVR** has not been tested yet.
- Standable's **mixed tracking** (combining Standable with SlimeVR,
  hardware trackers, etc.) works as it does on Windows.

## Options

| Command | What it does |
|---|---|
| `./standable install` | Install or repair (safe to re-run) |
| `./standable check` | Verify the installed setup |
| `./standable uninstall` | Remove everything this patch added |
| `./standable install --proton PATH` | Use a specific Proton build |
| `./standable install --build` | Rebuild the driver bridge from source (needs dev tools; prebuilt files are used otherwise) |
| `./standable install --no-safemode` | Persist `steamvr.enableSafeMode=false` so SteamVR stops hiding add-ons after a crash |

If several Proton builds are installed, the installer asks which one to
use. That choice is only a fallback. The driver and the game always use
the Proton picked in Steam, so the two stay in sync.

## Switching Protons

The driver and the game must always use **the same** Proton. To switch:

1. In **Steam**, right-click **Standable** → **Properties** →
   **Compatibility** → force a Proton.
2. If Steam was already open, **restart Steam**.
3. **Re-run `./install.sh`** - the game and driver resolve the new Proton at
   runtime, but a leftover wineserver from the old build can hold the prefix
   and block startup (Safe Mode ~20 s crash). The installer clears stale
   processes automatically.

### Driver-tested Proton builds

Verified end to end on the dev machine:

| Proton | Version tested | Result |
|---|---|---|
| `proton-cachyos-slr` | cachyos-11.0-20260703-slr | Works |
| `DW-Proton Latest` | dwproton-11.0-12 | Works |
| `Proton - Experimental` | experimental-11.0-20260826 | Works |
| `Proton-CachyOS Latest` | cachyos-11.0-20260703-slr | Works |
| `Proton-GE Latest` | GE-Proton11-6 | Works |
| `Proton 10.0` | 10.0 | Works |
| `Proton-GE RTSP Latest` | proton-rtsp-11.0-20260609-3 | Works |

If a build launches and closes instantly via Steam, switch to a different
Proton in Steam (→ Properties → Compatibility) and re-run `./install.sh`.
A leftover wineserver from a previous Proton is the usual cause of the
~20 s Safe-Mode crash; `./install.sh` clears it automatically.

### Render bug: checkerboard settings background

On some Protons, the settings panel background in VR shows a checkerboard
pattern instead of a plain color. Just a render bug, nothing breaks.
`proton-cachyos-slr` (the recommended build) renders it correctly. The
installer used to copy a dxvk-sarek build over the prefix for other Protons,
but that caused more trouble than the cosmetic fix was worth, so it no longer
does. If the pattern bothers you, switch to `proton-cachyos-slr`.

## Logging & diagnostics

All logs live in `~/.local/state/standable/`:

| File | What it records |
|---|---|
| `install.log` | Every installer run + `./standable check` full system dump |
| `hook.log` | Each game launch through the launch hook (Proton used, exit code) |
| `serverhelper.log` | Each driver-server launch (Proton used, wineservers before/after sweep, server exit) |

`./standable check` verifies the setup and appends the full system dump (OS,
GPU, display server, Steam/Proton/game, prefix, SteamVR settings, crash
signatures) to `install.log`:

```sh
./standable check
cat ~/.local/state/standable/install.log
```

When filing an issue, attach the `./standable check` log. If the driver or
game is failing to launch, also attach `hook.log` and `serverhelper.log` -
they show the actual launch attempt where `install.log` can't.

## Important

- Launch the game through Steam.
- Set the launch hook in Steam's Launch Options to get the desktop settings
  window while SteamVR runs (see Install). It's also what keeps the game and
  driver on the same Proton/prefix.
- The installer adds the Standable driver entry to
  `~/.config/openvr/openvrpaths.vrpath` without touching existing entries.
  Custom drivers stay in place.

## Troubleshooting

| Symptom | Fix |
|---|---|
| SteamVR crashes / enters safe mode ~20 s after startup | Run `./standable install` (clears stale wineservers), then restart SteamVR. If it persists, attach `serverhelper.log` |
| Game launches but no GUI | Make sure SteamVR is running; check `./standable check` |
| "Steam authentication failed" dialog | Launch through Steam, not by starting Standable.exe directly |
| Sliders don't apply in realtime | Re-run `./standable install`, restart SteamVR |
| T-pose fails intermittently | Re-run `./standable install` (repairs drive links), restart SteamVR |
| "no Proton builds found" | Pass `--proton /path/to/proton`, or install any Proton build |
| Anything else | Open an issue with the `./standable check` log attached |

## How it works

SteamVR loads a small Linux helper (`driver_standable.so`) as a driver. The
helper starts the Windows server (`ignition_server.exe`) with Proton inside
the game's folder, and the game is launched in host context by the launch
hook so its desktop settings window renders while SteamVR runs. Game and
driver pick the same Proton at startup and talk through shared memory. That
shared link is what makes settings updates instant.

The two known failure modes are handled by the installer:
- Proton needs a modern python (`from typing import Self`) but SteamVR's
  sandbox ships an older one, so Proton dies before the server starts and
  SteamVR aborts after ~20 s (Safe Mode). The installer deploys a `python3`
  shim that resolves a working interpreter; `./standable check` verifies it
  and offers to install Steam Linux Runtime 4.0 if missing.
- SteamVR force-aborts shutdown can leave the old Proton's Wine processes
  orphaned, holding the prefix and blocking the next launch. The launch
  scripts sweep foreign-Proton processes in the game's prefix before starting.

## Credits

- [Ignition](https://github.com/BnuuySolutions/Ignition) by Bnuuy Solutions (MIT)
- Standable Full Body Estimation by the Standable developers. This project is
  not affiliated with or endorsed by them.
