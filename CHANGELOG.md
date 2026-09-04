# Changelog

## v3.1.0

- **Respect the user's chosen Proton**: SteamVR's safe-mode state no longer
  hard-blocks standable across sessions no matter which Proton the game is
  forced to. When a transient handshake timeout trips SteamVR's ~21 s watchdog
  and drops the driver into safe mode, the launch script now clears the full
  block (`driver_standable.blocked_by_safe_mode` in `steamvr.vrsettings` **and**
  the `vrserver_crash_timestamp.txt` trigger file) before each boot. Previously
  only `enable`/`enableSafeMode` were cleared, leaving the driver silenced on
  every subsequent start until the user manually reset safe mode.
- **Auto-pick the Proton Steam has forced on the game** (`ConfigToolMapping`) so
  the driver always launches under the same build the user runs the game with;
  existing installs keep their current Proton rather than being silently
  switched.
- **Stale-service cleanup on Proton switches**: killing the previous build's
  leftover wineserver so a switch doesn't leave the app un-launchable.
- **Launch-time cross-Proton guard**: if a *different* Proton build ever left a
  wineserver (or orphaned wineboot/winedevice/xalia clients) holding the shared
  prefix, it silently blocked the Ignition server from starting — the driven
  handshake stalled past SteamVR's ~21 s watchdog and crashed into safe mode.
  The launch script now clears any Wine process owned by a foreign Proton (the
  configured Proton's own processes are left untouched) before starting the
   server, so switching/using any Proton can no longer deadlock the driver.
- **Fixed the recurring 21s watchdog crash**: `steam_api64.dll` was only deployed
  to `bin/linux64/` (the server's working dir), but the Windows driver DLL that
  imports it lives in `bin/win64/`. Wine resolves `driver_standable.dll`'s
  Steamworks dependency from the DLL's own directory, so without a copy beside it
  the driver failed to load, the IPC handshake never completed, and SteamVR
  aborted with a ~21 s watchdog timeout (safe-mode crash loop). The installer now
  deploys `steam_api64.dll` to `bin/win64/` as well, and `--check` verifies both.
- **Fixed Proton startup crash under SteamVR's Sniper sandbox**: the driver's
  `launch_serverhelper.sh` invokes `$PROTON run`, and Proton's launcher
  (`#!/usr/bin/env python3`) needs Python >= 3.11 (`from typing import Self`),
  but SteamVR loads drivers under the Sniper runtime, which only ships
  Python 3.9. Proton therefore died instantly with
  `ImportError: cannot import name 'Self' from 'typing'`, the server never
  connected, and SteamVR aborted with its ~21 s watchdog (safe-mode loop).
  The installer now deploys a `python3` interpreter shim next to the launch
  script: it uses a capable host python when available, otherwise runs the
  Soldier runtime's python3.13 through its own dynamic loader (which works
  despite Sniper's older glibc). Works with whatever Proton the user selects.
- **Proton switching without reinstall**: the driver and the launch hook now
  resolve the running Proton build on every boot via a shared
  `proton_resolve.sh` snippet. It prefers the prefix's own bookkeeping
  (`config_info` records the exact build dir Proton itself wrote — real-time,
  no Steam restart lag), then Steam's forced compat tool (`config.vdf`
  CompatToolMapping, matched with normalized names so spaces and built-in
  naming quirks work), then the install-time fallback. Flipping Proton in
  Steam's UI therefore takes effect on the next launch for both game and
  driver with no reinstall, and they can never mismatch over the shared
  prefix. Stale-service cleanup (`clear_stale_services`,
  `clear_foreign_wineservers`) is scoped to our own prefix via `/proc`
  environ, so unrelated games using the same Proton build are no longer
  killed, and built-in Protons under `steamapps/common` are handled too.
  `--check` reports a deployed-vs-forced mismatch (self-heals at boot,
  advisory only). Verified end-to-end (prefix creation, server boot, driver
  load, valid-provider handshake) on proton-cachyos-slr, Proton
  Experimental, DW-Proton, Proton-CachyOS, Proton-GE, and Proton-GE RTSP —
  see README's driver-tested table.
- **Windows-side driver registration hygiene** (`win_vrpath.sh`, run on every
  driver and game boot): the install used to seed the game's Windows-side
  `openvrpaths.vrpath` with a Linux game path, which is garbage under Wine,
  and stale `S:\` variants from previous Protons piled up next to it. The
  repair keeps exactly the current Proton's `S:\` entry and drops the rot.
  Note: this does not stop the game's per-boot dialog (see below) — the game
  rewrites that file itself on every boot — but it keeps the registration
  clean for everything that reads it.
- **Known upstream issue for the game dev**: the game rewrites the
  Windows-side `external_drivers` with its unix install dir on every boot
  (Steam API path, unresolvable under Wine) and then fails its own
  "directory exists" check, popping "the steamVR driver path is missing or
  incorrect!" every launch. Both buttons proceed in-memory with no disk
  change, so it always returns. Needs a game-side fix (write a DOS-form
  path, or skip the check once the driver is loaded).

## v3.0.2

- **Install on any Steam library**: when the game lives on a secondary drive
  (e.g. a shared dual-boot drive mounted under `/mnt`), the installer now finds
  it via `libraryfolders.vdf`, derives the Proton prefix from that drive's
  `steamapps/compatdata/<APP_ID>` (not the default Steam root), and points the
  `s:` drive at the correct library. This also fixes a pre-existing bug where
  the secondary-library paths in `libraryfolders.vdf` were never parsed, so
  off-root installs were silently ignored.

## v3.0.1

- **Fix SteamVR crash on fresh installs**: the Windows driver
  `driver_standable.dll` links against Valve's Steamworks runtime, but the
  SteamVR runtimes don't provide `steam_api64.dll`. On setups that never had
  another Steamworks title installed the Ignition server could not load the
  driver, the IPC handshake never completed, and SteamVR aborted after a
  ~21 s watchdog timeout and dropped into **safe mode**. The installer now
  vendors and deploys the official `steam_api64.dll` (Steamworks SDK
  redistributable) next to the shim, where Wine's DLL search path finds it.
- **Doctor**: `./standable check` now verifies `steam_api64.dll` is deployed
  and fails loudly when it isn't.
- **Supply chain**: `vendor/steam_api64.dll` added to `SHA256SUMS`;
  `BUILDING.md` documents its origin, hash and how to swap in your own copy.

## v3.0.0

- **Vendor Ignition**: installer deploys `libdriver_ignition.so` and
  `ignition_server.exe` directly from this repo, eliminating the manual
  Ignition install step.
- **Gamedrive convention detection**: launch scripts detect whether your
  Proton build manages `s:` via steamapps or the Steam parent dir, and
  adopt the matching convention automatically. Fixes the v2.1 regression
  where selecting Valve Proton Experimental would break `s:`.
- **Self-repair loop**: both launch scripts watch `s:` and recreate it if
  Proton's prefix maintenance deletes it (60-second window after launch).
- **Wine\VR key removed**: confirmed unnecessary; `vr_bootstrap.exe` does
  not check for it.
- **`./standable` CLI**: single entry point replacing the desktop-icon-first
  workflow (`./standable install`, `./standable gui`, `./standable check`).
- **Flatpak Steam**: clear error on detection instead of silent breakage.
- **glibc compatibility check**: warns at install time if the shipped
  `.so` won't load on older systems, points to `BUILDING.md`.
- **Supply-chain trust**: `vendor/SHA256SUMS`, `BUILDING.md` with upstream
  release hashes and build-from-source instructions.
