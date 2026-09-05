# Changelog

## v3.1.0

- SteamVR safe-mode no longer hard-blocks standable across sessions. The
  launch script now clears the full block (`driver_standable.blocked_by_safe_mode`
  in `steamvr.vrsettings` and the `vrserver_crash_timestamp.txt` file) before
  each boot, not just `enable`/`enableSafeMode`.
- The driver and launch hook resolve the Proton build at runtime via a shared
  `proton_resolve.sh`. They prefer the prefix's own bookkeeping (`config_info`),
  then Steam's forced compat tool (`config.vdf`), then the install-time
  fallback. Switching Proton in Steam's UI takes effect on the next launch for
  both game and driver, no reinstall.
- `clear_stale_services` / `clear_foreign_wineservers` kill the previous
  build's leftover wineserver so a Proton switch doesn't leave the app
  un-launchable. Scoped to our own prefix via `/proc` environ, so unrelated
  games are left alone. Also sweeps the orphaned `steam.exe`/`ignition_server.exe`
  tree left when SteamVR force-aborts shutdown.
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
  the Soldier runtime's python3.13.
- `win_vrpath.sh` (run on every driver/game boot) keeps exactly the current
  Proton's `S:\` entry in the game's Windows-side `openvrpaths.vrpath` and drops
  stale `S:\` variants and Linux paths. Does not stop the game's per-boot
  "steamVR driver path is missing" dialog — the game rewrites that file itself.
- The recurring 21 s `load_drivers` watchdog crash (issue #1, "steamvr error
  301") is fixed by a source patch on the Ignition build
  (`build/patches/ignition-rpc-timeout.patch`). RPC calls that would otherwise
  hang when the game isn't connected now time out, so the driver tears down
  instead of tripping SteamVR's watchdog.

## v3.0.2

- Install on any Steam library: the installer finds the game via
  `libraryfolders.vdf`, derives the prefix from that drive's
  `steamapps/compatdata/<APP_ID>`, and points `s:` at the correct library.

## v3.0.1

- Fresh-install SteamVR crash fixed: `driver_standable.dll` needs
  `steam_api64.dll` (Steamworks runtime), which SteamVR doesn't provide. The
  installer now vendors and deploys it.
- `./standable check` verifies `steam_api64.dll` is deployed.
- `vendor/steam_api64.dll` added to `SHA256SUMS`; origin documented in
  `BUILDING.md`.

## v3.0.0

- Ignition is vendored; the installer deploys `libdriver_ignition.so` and
  `ignition_server.exe` from this repo, no manual Ignition install step.
- Launch scripts detect the Proton `s:` convention (steamapps vs Steam parent
  dir) and adopt it automatically.
- Both launch scripts watch `s:` and recreate it if Proton's prefix
  maintenance deletes it (60 s after launch).
- `./standable` CLI is the single entry point (`install`, `gui`, `check`).
- Flatpak Steam gives a clear error instead of failing silently.
- Install-time glibc check warns if the shipped `.so` won't load.
- `vendor/SHA256SUMS` and `BUILDING.md` document upstream hashes and how to
  build from source.