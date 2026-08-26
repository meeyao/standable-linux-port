# Standable FBE — Linux patch (unofficial)

Runs Standable Full Body Estimation on Linux using the game's own Windows
binaries: driver, GUI window, realtime settings, T-pose calibration.
No game files are modified.

Based on [Ignition](https://github.com/BnuuySolutions/Ignition) by
Bnuuy Solutions (MIT), which provides the SteamVR↔Proton bridge this patch
deploys; see `vendor/IGNITION-LICENSE`. Prefer not to use the prebuilt
binaries we ship? [BUILDING.md](BUILDING.md) covers hash verification,
substituting the official upstream release, and building from source.

## Install

Requires an Arch-based system with:

- **Steam** and **SteamVR** installed
- Standable Full Body Estimation installed (AppId **2370570**)
- Any Proton build (Steam's bundled Proton works)

```sh
git clone https://github.com/meeyao/standable-linux-port.git
cd standable-linux-port
./install.sh
```

Then:

1. Start **SteamVR**
2. Launch the **Standable GUI** desktop icon

That's it: sliders apply in realtime and T-pose calibration works.

## Options

| Command | What it does |
|---|---|
| `./install.sh` | Install or repair (safe to re-run) |
| `./install.sh --check` | Verify a running setup |
| `./install.sh --uninstall` | Remove everything the installer added |
| `./install.sh --proton PATH` | Use a specific Proton build |

If several Proton builds are installed you'll be asked which one to use.
Whatever you pick, don't mix builds later without re-running `./install.sh`.

## Important

- Launch the GUI only through the desktop icon. Launching via Steam's Play
  button runs it inside Steam's sandbox, which breaks rendering and
  realtime settings.
- Don't change the game's compatibility tool after installing; if you do,
  run `./install.sh` again so both sides use the same Proton build.
- Keep a few GB of disk free — a full disk makes Proton's prefix setup fail
  silently.

## Troubleshooting

| Symptom | Fix |
|---|---|
| GUI opens then instantly closes | Run `./install.sh --check`; make sure SteamVR is running first |
| Sliders don't apply in realtime | Re-run `./install.sh`, restart SteamVR |
| T-pose fails intermittently | Re-run `./install.sh` (repairs drive links), restart SteamVR |
| "no Proton builds found" | Pass `--proton /path/to/proton`, or install any Proton build |
| Anything else | Open an issue with `--check` output attached |

## How it works

SteamVR loads a small Linux shim (`driver_standable.so`) as a native driver.
The shim spawns Ignition's `ignition_server.exe` under Proton in the game's
existing prefix, which loads the game's own Windows driver DLL. The GUI also
runs under that same prefix and Proton build, so GUI and driver share a
single wine server; the named pipes between them are what make settings
updates realtime. A few helper stubs satisfy the GUI's SteamVR presence checks, and
the installer keeps the prefix's drive links alive against Proton's
per-launch maintenance passes.

## Credits

- [Ignition](https://github.com/BnuuySolutions/Ignition) — Bnuuy Solutions (MIT)
- Standable Full Body Estimation — the Standable developers; this project is
  not affiliated with or endorsed by them.
