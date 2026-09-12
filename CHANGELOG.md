# Changelog

## Unreleased

- The installer seeds the current-Proton `S:\` game path into Linux
  `~/.config/openvr/openvrpaths.vrpath` next to the Linux path. Proton
  copies that file into the prefix on every launch and the game validates
  its driver path there with a raw Win32 check, which a bare `/home/...`
  entry can never pass under Wine - hence the per-boot "driver path is
  missing"   dialog (the driver itself always loaded fine). Verified by
  diffing the Windows-side file before/after the game's own Fix It button,
  which writes exactly the seeded form. `./standable check` verifies the
  seed entry.
- `launch_serverhelper.sh` pins CWD to the driver directory before starting
  the server. `ignition_server` resolves its `driver_dll`
  (`../win64/driver_standable.dll`) against CWD, so inheriting vrserver's
  boot-dependent CWD made driver load a coin flip: it worked when vrserver
  happened to boot with a compatible CWD and failed with silent exit 1
  (vrserver 105s, no driver) otherwise. Proven with loader traces showing
  the miss (`.../common/win64/...`) vs the hit (`.../bin/win64/...`).

## v1.0.0

First major release. testing/rc is the maintained branch.

- The old `./standable gui` command and the "Standable GUI" desktop entry are
  gone. The launch hook replaces them: set it in Steam Launch Options, then
  launch through Steam. Without the hook the game still runs, the settings
  window just shows in VR only.
- A SteamVR crash left the driver "blocked by a previous safe mode event" on
  the next boot, and only a re-install cleared it. The launch hook now clears
  the block markers on every game launch, and `./standable check` reports
  them instead of failing silently.
- The wineserver sweep read /proc environ for every wine-ish process on the
  box, ~5 s per launch on a loaded machine. SteamVR probes a driver twice
  (~8 s apart) and drops it with VRInitError 105 when the server hasn't
  handshook yet, so those seconds decided boot success by luck (the
  intermittent "driver won't load even though nothing crashed"). The sweep
  now scans candidates with one pgrep shot.
- `ignition_server` output is captured to `~/.local/state/standable/server.out`;
  an instant exit-0 left no trace at all before.
- Timestamped backups are pruned to the newest 2 per file; installs stacked
  dozens of .bak files in bin/linux64.
- SteamVR safe-mode no longer hard-blocks standable across sessions. The
  launch script now clears the full block (`driver_standable.blocked_by_safe_mode`
  in `steamvr.vrsettings` and the `vrserver_crash_timestamp.txt` file) before
  each boot, not just `enable`/`enableSafeMode`.
- The driver and launch hook resolve the Proton build at runtime via a shared
  `proton_resolve.sh`. They prefer the prefix's own bookkeeping (`config_info`),
  then Steam's forced compat tool (`config.vdf`), then the install-time
  fallback. After switching Proton in Steam's UI, re-run `./install.sh` so
  stale Wine processes from the old build are cleared.
- `clear_stale_services` / `clear_foreign_wineservers` kill the previous
  build's leftover wineserver so a Proton switch doesn't leave the app
  un-launchable. Scoped to the game's own prefix via `/proc` environ, so
  unrelated games are left alone. Also sweeps the orphaned
  `steam.exe`/`ignition_server.exe` tree left when SteamVR force-aborts
  shutdown.
- The launch hook now runs the game in host context (`$PROTON run`) instead of
  chaining Steam's `%command%`. Chaining registered the app as a
  `steam.overlay` client that SteamVR dropped immediately. Direct run keeps the
  desktop GUI window while SteamVR runs.
- `steam_api64.dll` is deployed to `bin/win64/` as well as `bin/linux64/`.
  The Windows driver imports it from its own directory, so without a copy
  beside it the driver failed to load and SteamVR aborted after a ~21 s
  watchdog timeout.
- Proton crashed on startup under SteamVR's Sniper sandbox because its launcher
  needs Python >= 3.11 (`from typing import Self`) but Sniper only ships 3.9.
  The installer now deploys a `python3` shim that uses a capable host python or
  the Steam Linux Runtime 4.0 python3.13.
- `win_vrpath.sh` (run on every driver/game boot) keeps exactly the current
  Proton's `S:\` entry in the game's Windows-side `openvrpaths.vrpath` and drops
  stale `S:\` variants and Linux paths. Does not stop the game's per-boot
  "steamVR driver path is missing" dialog - the game rewrites that file itself.
- The `load_drivers` watchdog crash (issue #1, "steamvr error 301") was a
  leftover wineserver from a previous Proton holding the prefix; the
  install-time `clear_stale_services` sweep clears it. The Ignition source
  patch (`build/patches/ignition-rpc-timeout.patch`) bounds RPC calls so a
  stalled game driver can't wedge SteamVR's shutdown watchdog either.

## v0.1.2

- Install on any Steam library: the installer finds the game via
  `libraryfolders.vdf`, derives the prefix from that drive's
  `steamapps/compatdata/<APP_ID>`, and points `s:` at the correct library.

## v0.1.1

- Fresh-install SteamVR crash fixed: `driver_standable.dll` needs
  `steam_api64.dll` (Steamworks runtime), which SteamVR doesn't provide. The
  installer now vendors and deploys it.
- `./standable check` verifies `steam_api64.dll` is deployed.
- `vendor/steam_api64.dll` added to `SHA256SUMS`; origin documented in
  `MANUAL.md`.

## v0.1.0

- Ignition is vendored; the installer deploys `libdriver_ignition.so` and
  `ignition_server.exe` from this repo, no manual Ignition install step.
- Launch scripts detect the Proton `s:` convention (steamapps vs Steam parent
  dir) and adopt it automatically.
- Both launch scripts watch `s:` and recreate it if Proton's prefix
  maintenance deletes it (60 s after launch).
- `./standable` CLI is the single entry point (`install`, `check`,
  `uninstall`).
- Flatpak Steam gives a clear error instead of failing silently.
- Install-time glibc check warns if the shipped `.so` won't load.
- `vendor/SHA256SUMS` and `MANUAL.md` document upstream hashes and how to
  build from source.
