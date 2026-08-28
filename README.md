# Standable FBE Linux Patch (Unofficial)

Runs Standable Full Body Estimation on Linux using the game's own Windows
binaries: driver, GUI window, realtime settings, T-pose calibration.
No game files are modified.

Based on [Ignition](https://github.com/BnuuySolutions/Ignition) by
Bnuuy Solutions (MIT), which provides the SteamVR-Proton bridge this patch
deploys; see `vendor/IGNITION-LICENSE`. This project is licensed under
[MIT](LICENSE). Prefer not to use the prebuilt binaries in `vendor/`?
[BUILDING.md](BUILDING.md) covers hash verification, substituting the
official upstream release, and building from source.

## Install

Requires Linux with a native (non-Flatpak) Steam install:

- **Steam** and **SteamVR** installed
- Standable Full Body Estimation installed (AppId **2370570**)
- Any Proton build (Steam's bundled Proton works)

```sh
git clone https://github.com/meeyao/standable-linux-port.git
cd standable-linux-port
./install.sh
```

Then:

```sh
./standable gui     # with SteamVR running
```

Sliders apply in realtime and T-pose calibration works. The installer also
creates a "Standable GUI" desktop entry if you prefer clicking.

## Compatibility

- Tested with **Steam Link** (on-PC and local network).
- **WiVRN** is not supported; the SteamVR driver loading path it uses
  is incompatible with this patch.
- **ALVR** has not been tested yet.
- Standable's **mixed tracking** (combining Standable with SlimeVR,
  hardware trackers, etc.) works as it does on Windows.

## Options

| Command | What it does |
|---|---|
| `./standable install` | Install or repair (safe to re-run) |
| `./standable check` | Verify the installed setup |
| `./standable uninstall` | Remove everything this patch added |
| `./standable gui` | Launch the GUI |
| `./standable install --proton PATH` | Use a specific Proton build |

If several Proton builds are installed you'll be asked which one to use.
Whatever you pick, don't mix builds later without re-running
`./standable install`.

## Important

- Launch the GUI only via `./standable gui` (or the desktop entry). Running
  it through Steam's Play button puts it inside Steam's sandbox, which
  breaks rendering and realtime settings.
- Don't change the game's compatibility tool after installing; if you do,
  run `./standable install` again so both sides use the same Proton build.
- The installer merges the Standable driver entry into
  `~/.config/openvr/openvrpaths.vrpath` without overwriting any existing
  entries. If you already have custom drivers configured, they will be
  preserved.

## Troubleshooting

| Symptom | Fix |
|---|---|
| SteamVR crashes / enters safe mode ~20 s after startup | Run `./standable install` (deploys `steam_api64.dll`, the driver's Steamworks runtime), then restart SteamVR |
| GUI opens then instantly closes | Run `./standable check`; make sure SteamVR is running first |
| Sliders don't apply in realtime | Re-run `./standable install`, restart SteamVR |
| T-pose fails intermittently | Re-run `./standable install` (repairs drive links), restart SteamVR |
| "no Proton builds found" | Pass `--proton /path/to/proton`, or install any Proton build |
| Anything else | Open an issue with `--check` output attached |

## How it works

SteamVR loads a small Linux shim (`driver_standable.so`) as a native driver.
The shim spawns Ignition's `ignition_server.exe` under Proton in the game's
existing prefix, which loads the game's own Windows driver DLL. The GUI also
runs under that same prefix and Proton build, so GUI and driver share a
single wine server; the named pipes between them are what make settings
updates realtime. A few helper stubs satisfy the GUI's SteamVR presence
checks, and the installer keeps the prefix's drive links alive against
Proton's per-launch maintenance passes.

## Credits

- [Ignition](https://github.com/BnuuySolutions/Ignition) by Bnuuy Solutions (MIT)
- Standable Full Body Estimation by the Standable developers. This project is
  not affiliated with or endorsed by them.
