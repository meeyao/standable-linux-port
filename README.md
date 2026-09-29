# Standable FBE Linux Patch (Unofficial)

Run **Standable Full Body Estimation on Linux** using its Windows binaries through Proton.

This patch adds the Linux bits Standable needs without modifying or replacing Standable's original files. It adds a few helper files in Standable's `bin/linux64/` folder and places `steam_api64.dll` beside the Windows driver in `bin/win64/`, plus a SteamVR driver, desktop settings window support, realtime settings, and T-pose calibration.

Some code was written with LLM assistance. It has been reviewed and tested, but skim it before relying on it, especially anything that kills processes or changes config files.

## Quick Start

### 1. Install the requirements

You need:

* Native Steam (not Flatpak)
* SteamVR
* Standable Full Body Estimation (AppID `2370570`)
* A Proton version
* Steam Linux Runtime 4.0 (Sniper)

You install SteamVR and Standable yourself. The installer sets up everything else, including Steam Linux Runtime 4.0.

### 2. Pick a Proton for Standable

In Steam:

**Standable → Properties → Compatibility**

Enable:

> Force the use of a specific Steam Play compatibility tool

Pick a Proton.

If Steam was already open, **restart Steam** after changing it.

Some known-working versions are listed below.

### 3. Install the patch

```sh
git clone https://github.com/meeyao/standable-linux-port.git
cd standable-linux-port
./install.sh
```

You can safely run the installer again later. It repairs the installation and picks up changes.

To see what it would do without changing anything:

```sh
./install.sh --dry-run
```

### 4. Add the launch option

Go back to:

**Standable → Properties → General → Launch Options**

Add:

```sh
bash ~/.local/bin/standable_launch_hook.sh %command%
```

This runs Standable in the host environment, so its desktop settings window works while SteamVR is running and Standable and the driver stay on one shared Proton prefix.

### 5. Start SteamVR

Start SteamVR **before** launching Standable.

The Standable trackers should appear in SteamVR as soon as it starts, before you launch the Standable app.

If they don't:

```sh
./standable check
```

Then see [Troubleshooting](#troubleshooting).

### 6. Launch Standable

Click **Play** on Standable in Steam.

The normal Standable settings window should appear on your desktop while SteamVR is running.

**Always launch Standable through Steam.**

Launching `Standable.exe` directly will fail Steam authentication.

---

## Requirements

### Steam

You need a normal native Steam installation.

Flatpak Steam is not supported.

### SteamVR

Install SteamVR normally through Steam.

### Standable

Install **Standable Full Body Estimation** from Steam.

AppID:

```text
2370570
```

The installer finds Standable even if it is installed on another library drive.

### Proton

Standable needs a Proton build forced through Steam.

These have been tested:

| Proton                | Version tested              |
| --------------------- | --------------------------- |
| proton-cachyos-slr    | cachyos-11.0-20260703-slr   |
| DW-Proton Latest      | dwproton-11.0-12            |
| Proton Experimental   | experimental-11.0-20260826  |
| Proton-CachyOS Latest | cachyos-11.0-20260703-slr   |
| Proton-GE Latest      | GE-Proton11-6               |
| Proton 10             | 10.0                        |
| Proton-GE RTSP Latest | proton-rtsp-11.0-20260609-3 |

If one Proton doesn't work, try another and run the installer again.

### Steam Linux Runtime 4.0

SteamVR runs the driver inside its Steam Linux Runtime 4.0 (Sniper) environment, which only ships Python 3.9. Modern Proton launchers need Python 3.11 or newer (`from typing import Self`), so without a newer Python Proton dies before the server starts and SteamVR aborts after ~20 seconds.

The installer deploys a `python3` shim that finds a working interpreter, and it checks for the Runtime and offers to install it if it is missing.

You don't need to configure anything. Just leave it installed.

---

## Commands

The easiest way to interact with the patch is `./standable`.

| Command                             | What it does                                   |
| ----------------------------------- | ---------------------------------------------- |
| `./standable install`               | Install or repair the patch                    |
| `./standable check`                 | Check the installation and collect diagnostics |
| `./standable uninstall`             | Remove everything added by this patch          |
| `./standable install --proton PATH` | Use a specific Proton                          |
| `./standable install --build`       | Build the driver bridge from source            |
| `./standable install --no-safemode` | Stop SteamVR from hiding drivers after a crash |

`./standable` and `./install.sh` are both supported.

---

## Troubleshooting

### Start here

If something isn't working, run:

```sh
./standable check
```

It checks the installation and writes diagnostics to:

```text
~/.local/state/standable/install.log
```

### No Standable skeleton in SteamVR

Fully quit SteamVR and try:

```sh
pkill -f ignition_server.exe
```

Then start SteamVR again.

If that doesn't help:

```sh
./standable install
```

and restart SteamVR.

### VRInitError_Init_InterfaceNotFound (105)

SteamVR loaded the driver but its server never answered.

This usually means a stale server from an earlier session is blocking the helper:

1. Fully quit SteamVR.
2. Run:

```sh
pkill -f ignition_server.exe
```

3. Start SteamVR again.

If it still happens, run:

```sh
./standable install
```

Then restart SteamVR.

`./standable check` flags this error automatically.

### SteamVR crashes or enters Safe Mode after ~20 seconds

Run:

```sh
./standable install
```

Then restart SteamVR.

This usually means an old Proton/Wine process is still holding the Standable prefix.

### SteamVR says the driver was blocked by Safe Mode

Run:

```sh
./standable install
```

Then restart SteamVR.

The installer clears the block left behind by previous crashes.

### Standable launches but there is no desktop window

Make sure:

1. SteamVR is running.
2. The launch option from [Quick Start](#quick-start) is set.
3. `./standable check` passes.

### "Steam authentication failed"

Launch Standable through **Steam**.

Do not run `Standable.exe` directly.

### "SteamVR driver path is missing"

Usually harmless. The driver can still load.

Run:

```sh
./standable install
```

The installer fixes the path used by Standable's check.

### Driver keeps exiting with code 1

Run:

```sh
./standable check
```

If it reports stale `xalia.exe` processes, kill the PIDs marked `STALE`:

```sh
kill <PID>
```

Then restart SteamVR.

### Sliders don't update in realtime

Run:

```sh
./standable install
```

Then restart SteamVR.

### T-pose calibration doesn't work

Run:

```sh
./standable install
```

Then restart SteamVR.

### Checkerboard background in the settings window

This is a cosmetic Proton rendering bug.

It doesn't normally affect Standable.

`proton-cachyos-slr` renders the window correctly from the start.

### "No Proton builds found"

Either install a Proton build or tell the installer where it is:

```sh
./standable install --proton /path/to/proton
```

### Still broken?

Open an issue and attach:

```sh
~/.local/state/standable/install.log
```

If Standable or the driver fails to start, also attach:

```text
~/.local/state/standable/serverhelper.log
~/.local/state/standable/server.out
~/.local/state/standable/hook.log
```

---

## Switching Proton Versions

You only need to do this if you want to change Proton.

**Standable and the driver must use the same Proton**.

### 1. Change Proton in Steam

**Standable → Properties → Compatibility**

Pick the Proton you want.

### 2. Restart Steam

If Steam was already running when you changed it, restart Steam.

### 3. Run the installer again

```sh
./install.sh
```

### 4. Restart SteamVR

That's it.

The installer copies the required Proton `vrclient` files and clears old Wine processes that can otherwise keep the old Proton alive.

---

## Logging

Logs are stored here:

```text
~/.local/state/standable/
```

| File                | Contains                                                |
| ------------------- | ------------------------------------------------------- |
| `install.log`       | Installer runs and full `./standable check` diagnostics |
| `serverhelper.log`  | Driver/server launches and Proton information           |
| `server.out`        | Standable/driver server output                          |
| `proton-server.log` | Proton startup output for the driver server             |
| `hook.log`          | Standable launches through the launch hook              |
| `game.log`          | Standable's own output                                  |

For a bug report, start with:

```sh
./standable check
```

Then attach the relevant logs.

---

## Compatibility

* **Steam Link:** tested and working
* **WiVRN:** work in progress
* **ALVR:** unstable
* **Mixed tracking:** supported, including Standable + SlimeVR + hardware trackers
* Existing OpenVR drivers are left alone

The installer adds Standable to:

```text
~/.config/openvr/openvrpaths.vrpath
```

without removing existing driver entries.

---

## How It Works

If you're curious about what's actually happening:

SteamVR loads a small Linux driver:

```text
driver_standable.so
```

That driver starts Standable's Windows server:

```text
ignition_server.exe
```

using Proton.

The launch hook starts Standable in the host environment so its desktop settings window can appear normally while SteamVR is running.

Standable and the driver use the same Proton prefix and communicate through shared memory, which is what allows settings to update in realtime.

The installer also handles two annoying Linux/Proton problems:

* SteamVR's runtime can have an old Python version that is too old for modern Proton launchers. The installer provides a `python3` shim and checks that a usable Python is available.
* SteamVR can leave Wine/Proton processes behind after shutting down. Those processes can keep the prefix locked, so the installer cleans up stale processes before starting again.

---

## Manual Installation / Building

Don't need this unless you want to replace the bundled binaries or build things yourself.

See [MANUAL.md](MANUAL.md) for:

* Hash verification
* Replacing the bundled binaries with official upstream releases
* Building the driver bridge from source

The bundled Ignition components come from [Bnuuy Solutions/Ignition](https://github.com/BnuuySolutions/Ignition) and are licensed under MIT. See `vendor/IGNITION-LICENSE`.

---

## Credits

* [Ignition](https://github.com/BnuuySolutions/Ignition) by Bnuuy Solutions, MIT
* Standable Full Body Estimation by the Standable developers

This project is licensed under [MIT](LICENSE). It is unofficial and is not
affiliated with or endorsed by Standable.
