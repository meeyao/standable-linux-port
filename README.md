# Standable FBE Linux Patch (Unofficial)

Runs Standable Full Body Estimation on Linux using the game's own Windows
binaries: driver, GUI window, realtime settings, T-pose calibration.
The game's own files stay untouched. The patch only adds its own helper
files next to them.

Based on [Ignition](https://github.com/BnuuySolutions/Ignition) by
Bnuuy Solutions (MIT). It provides the SteamVR-Proton bridge used here;
see `vendor/IGNITION-LICENSE`. This project is licensed under
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

Then launch it through Steam as you would any other title. Plain **Play**
works. The driver uses the same Proton as the game, so no reinstall is
needed after switching Proton. Start **SteamVR**, then click **Play** on
Standable.

Optional: if the settings background in VR shows a checkerboard pattern,
set this launch option — right-click **Standable** in Steam →
**Properties** → **Launch Options**, set:
```
bash ~/bin/standable_launch_hook.sh %command%
```

The game can be on any Steam library drive. The installer finds it.

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

If several Proton builds are installed, the installer asks which one to
use. That choice is only a fallback. The driver and the game always use
the Proton picked in Steam, so the two stay in sync.

## Switching Protons

The driver and the game must always use **the same** Proton. To switch:

1. In **Steam**, right-click **Standable** → **Properties** →
   **Compatibility** → force a Proton.
2. If Steam was already open, **restart Steam**.
3. **Launch** as usual. No reinstall needed. Both pick up the new Proton
   on their own.

### Driver-tested Proton builds

Every build below was tested end to end and works. Any normal Proton
install should work. None were found unstable:

| Proton | Version tested | Result |
|---|---|---|
| `proton-cachyos-slr` | cachyos-11.0-20260703-slr | Works |
| `Proton - Experimental` | experimental-11.0-20260826 | Works |
| `DW-Proton Latest` | dwproton-11.0-12 | Works |
| `Proton-CachyOS Latest` | cachyos-11.0-20260703-slr | Works |
| `Proton-GE Latest` | GE-Proton11-6 | Works |
| `Proton-GE RTSP Latest` | proton-rtsp-11.0-20260609-3 | Works |

### Render bug: checkerboard settings background

On some Protons, the settings panel background in VR shows a checkerboard
pattern instead of a plain color. Just a render bug, nothing breaks. These
Protons already carry the fix:

- `proton-cachyos-slr`
- `dwproton`
- `dwproton-signed`

On other Protons, `install.sh` warns and copies the fix files over by
itself. Each Proton ships its own copy of the fix, so the look can vary
slightly between them.

## Logging & diagnostics

Every run writes a full transcript to `~/.local/state/standable/install.log`
(`--log FILE` writes there instead). `--diagnose` adds system info to the
same log:

```sh
./install.sh --diagnose      # or: ./standable check --diagnose
cat ~/.local/state/standable/install.log
```

When filing an issue, attach the `--diagnose` log instead of pasting
terminal output. It has everything needed.

## Important

- Launch the game through Steam. Plain **Play** is enough.
- The `standable_launch_hook.sh` launch option is optional. It only fixes
  the checkerboard background pattern. Nothing else needs it.
  See [Render bug](#render-bug-checkerboard-settings-background).
- The installer adds the Standable driver entry to
  `~/.config/openvr/openvrpaths.vrpath` without touching existing entries.
  Custom drivers stay in place.

## Troubleshooting

| Symptom | Fix |
|---|---|
| SteamVR crashes / enters safe mode ~20 s after startup | Run `./standable install`, then restart SteamVR |
| Game launches but no GUI | Make sure SteamVR is running; check `./standable check` |
| "Steam authentication failed" dialog | Launch through Steam, not by starting Standable.exe directly |
| Sliders don't apply in realtime | Re-run `./standable install`, restart SteamVR |
| T-pose fails intermittently | Re-run `./standable install` (repairs drive links), restart SteamVR |
| "no Proton builds found" | Pass `--proton /path/to/proton`, or install any Proton build |
| Anything else | Open an issue with `--diagnose` output attached |

## How it works

SteamVR loads a small Linux helper (`driver_standable.so`) as a driver.
The helper starts the Windows server with Proton inside the game's folder.
Game and driver pick the same Proton at startup and talk through shared
memory. That shared link is what makes settings updates instant.

## Credits

- [Ignition](https://github.com/BnuuySolutions/Ignition) by Bnuuy Solutions (MIT)
- Standable Full Body Estimation by the Standable developers. This project is
  not affiliated with or endorsed by them.
