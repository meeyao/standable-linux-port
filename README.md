# Standable Full Body Estimation — Linux patch (unofficial)

Runs Standable FBE on Linux with the stock Windows binaries: full driver,
GUI window, realtime settings, T-pose calibration. No game files are modified.

## Install (3 steps)

Requires: Arch-based Linux, Steam + **SteamVR** installed, and the game
(Steam AppId **2370570**) installed. Any Proton build works.

```sh
git clone <repo-url> && cd standable-linux-port-public
./install.sh
```

Then:

1. Start **SteamVR**
2. Launch the **Standable GUI** desktop icon

That's it.

- Multiple Proton builds installed? The installer asks which to use.
- Force a specific one: `./install.sh --proton /path/to/Proton/files/proton`
- Verify a running setup: `./install.sh --check`
- Remove everything: `./install.sh --uninstall`

## Important

- **Never launch the GUI via Steam's Play button.** Steam's sandbox breaks
  IPC and rendering. Always use the desktop icon (or `~/bin/standable-gui`).
- If Steam's compatibility tool is set for the game, point it at the *same*
  Proton build the installer chose — or simply never launch it from Steam.
- Low disk space silently breaks Proton prefix setup. Keep a few GB free.

## Troubleshooting

| Symptom | Fix |
|---|---|
| GUI opens and instantly closes | Re-run `./install.sh`; check `--check` output; ensure SteamVR is running first |
| Sliders don't apply in realtime | Another wineserver is running from a different app — reboot and use only the desktop icon |
| T-pose fails intermittently | Re-run `./install.sh` (repairs drive links), then restart SteamVR |
| `no Proton builds found` | Pass `--proton /path/to/proton`, or install any Proton build |

## How it works (short)

SteamVR loads the driver shim natively; the shim spawns the Windows driver
server under Proton inside the game's existing prefix. The GUI runs under the
*same* Proton + prefix so both share one wine server — that shared server is
what makes named-pipe settings updates realtime. A few helper stubs satisfy
the GUI's SteamVR presence checks, and the installer keeps the prefix's drive
links alive against Proton's per-launch maintenance passes.

Unofficial community project — not affiliated with the Standable developers.
