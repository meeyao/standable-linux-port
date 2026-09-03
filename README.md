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

Then launch it through Steam as you would any other title:

1. Right-click **Standable** in Steam → **Properties** → **Launch Options**, set:
   ```
   bash ~/bin/standable_launch_hook.sh %command%
   ```
2. Start **SteamVR**, then click **Play** on Standable.

The launch hook runs the game and driver on the same Proton build over one
prefix (their IPC depends on a shared wine server) and passes the appid
context the game's Steam authentication requires.

The game can live on any Steam library (including a secondary/dual-boot drive
mounted outside the default Steam root); the installer finds it via
`libraryfolders.vdf` and sets up the Proton prefix and `s:` drive to match.

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
| `./standable install --proton PATH` | Use a specific Proton build |
| `./standable install --build` | Rebuild the Ignition shim from source (`--force` rebuilds even if cached; needs clang/lld/cmake/ninja + Windows SDK via xwin, else prebuilt `vendor/` copies are used) |

If several Proton builds are installed you'll be asked which one to use.
Whatever you pick, don't mix builds later without re-running
`./standable install`.

## Switching Protons

You can use any Proton build, but the driver and game must always agree on
**the same one** (they share one prefix/wineserver — split wineservers break
their IPC). To use a different Proton:

1. **Steam** → right-click **Standable** → **Properties** → **Compatibility** →
   check "Force the use of a specific Steam Play compatibility tool" → pick a
   Proton (e.g. `dwproton`).
2. **Re-run `./standable install`**. This re-reads Steam's choice and
   regenerates the launch hooks to match. The installer also clears any stale
   wineserver still running under the *previous* Proton — that's what silently
   made "Play" do nothing after a switch before.
3. **Launch** through Steam as usual.

### Known-good Protons (in-VR background)

The in-VR overlay background renders as a **checker/test pattern** under a
Proton whose D3D11 is stock DXVK. Only VR-tuned `dxvk-sarek` renders it
correctly. Protons verified to work out of the box:

- `proton-cachyos-slr`
- `dwproton`
- `dwproton-signed`

When you pick one that lacks sarek (plain Proton-GE, Valve stock), `install.sh`
warns and layers a sarek copy over the prefix automatically — but the renderer
bytes are then borrowed from one of the known-good Protons, so for the most
predictable result prefer one of the three above.

### Note on bytes

`dxvk-sarek` builds are **not byte-identical across Protons**. Each ships its
own build, so switching between the known-good Protons can produce subtly
different rendering. That's expected; all of them fix the checker pattern.

## Logging & diagnostics

Every run writes a full transcript to `~/.local/state/standable/install.log`
(`--log FILE` writes there instead). `--diagnose` appends a system dump —
OS/kernel, GPU/Vulkan, display server, Steam/Proton/game/prefix, SteamVR
settings, and the vrserver.txt tail — to the same log:

```sh
./install.sh --diagnose      # or: ./standable check --diagnose
cat ~/.local/state/standable/install.log
```

When filing an issue, attach the `--diagnose` log instead of pasting the
terminal output — it bundles everything needed.

## Important

- Launch the game via Steam with the launch hook set (see Install). Don't run
  Standable through Steam's plain Play button without the hook — the driver
  and game must share one Proton build and prefix.
- Don't change the game's compatibility tool after installing; if you do,
  run `./standable install` again so both sides use the same Proton build.
  See [Switching Protons](#switching-protons).
- The installer merges the Standable driver entry into
  `~/.config/openvr/openvrpaths.vrpath` without overwriting any existing
  entries. If you already have custom drivers configured, they will be
  preserved.

## Troubleshooting

| Symptom | Fix |
|---|---|
| SteamVR crashes / enters safe mode ~20 s after startup | Run `./standable install` (deploys `steam_api64.dll`, the driver's Steamworks runtime), then restart SteamVR |
| Game launches but no GUI | Make sure the launch hook is set and SteamVR is running; check `./standable check` |
| "Steam authentication failed" dialog | Re-run `./standable install` (the hook exports `SteamAppId`); don't launch the game without the hook |
| Sliders don't apply in realtime | Re-run `./standable install`, restart SteamVR |
| T-pose fails intermittently | Re-run `./standable install` (repairs drive links), restart SteamVR |
| "no Proton builds found" | Pass `--proton /path/to/proton`, or install any Proton build |
| Anything else | Open an issue with `--check` output attached |

## How it works

SteamVR loads a small Linux shim (`driver_standable.so`) as a native driver.
The shim spawns Ignition's `ignition_server.exe` under Proton in the game's
existing prefix, which loads the game's own Windows driver DLL. The game runs
under that same prefix and Proton build (the launch hook enforces it), so the
game and driver share a single wine server; the named pipes between them are
what make settings updates realtime. The installer keeps the prefix's drive
links alive against Proton's per-launch maintenance passes.

## Credits

- [Ignition](https://github.com/BnuuySolutions/Ignition) by Bnuuy Solutions (MIT)
- Standable Full Body Estimation by the Standable developers. This project is
  not affiliated with or endorsed by them.
