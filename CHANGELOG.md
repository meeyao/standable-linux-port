# Changelog

## Unreleased

### Fixes

* Fixed another cause of `VRInitError_Init_InterfaceNotFound` (105) after
  switching Proton or restarting SteamVR. A stale `ignition_server.exe` could
  stop the new server from starting. The helper now only matches the current
  session.
* `./standable check` now detects the actual SteamVR 105 error instead of
  reporting everything as OK.
* Fixed a fresh-install crash where SteamVR's Sniper runtime could not run the
  helper because it doesn't include `ps` or `pgrep`. The helper now uses
  `$PPID` and `/proc` directly.
* Fixed a driver startup hang caused by an unanswered Ignition handshake.
  The handshake now times out after 15 seconds instead of waiting 60 seconds
  and taking down SteamVR's `load_drivers` thread.
* `./standable check` now detects the SteamVR `load_drivers` watchdog crash.
* Fixed intermittent driver loading failures caused by Ignition registering
  its RPC function after starting its listener. The registration now happens
  first.
* Fixed the server helper deleting the driver's `ignition_ipc_*` shared-memory
  files. This could break the handshake.
* Fixed duplicate helpers killing the active server during the stale-process
  cleanup.
* The server is now started directly through Proton's Wine binary.
* The PSVR2 registry import is delayed until after the driver handshake.
* The server stays alive through SteamVR's retry window.
* The server helper now starts from the driver directory. This fixes cases
  where Ignition looked for the Windows driver DLL in the wrong directory.
* Added the current Proton's `S:\` game path to `openvrpaths.vrpath`. This fixes
  the recurring "SteamVR driver path is missing" dialog.
* `./standable check` now verifies the `S:\` path entry.
* The stale-wineserver scan is now shared by the driver helper and launch hook,
  instead of having separate copies that could get out of sync.
* `--uninstall` now actually removes the files and settings added by the
  installer. It also refuses to run while SteamVR is running.
* Fixed `--dry-run` accidentally running file operations.
* `--build-from-source` now builds against the pinned Ignition commit
  `6bb3c8a`, matching the source used for the shipped binaries.

### Diagnostics

* `./standable check` now reports when the server helper is repeatedly skipping
  launches without ever starting a server.
* `./standable check` now shows the relevant lines from SteamVR's
  `vrserver.txt` when it finds the 105 error.
* Failed launches now actually leave a `server.out` behind. Previously the
  helper never reached the launch line, so it left no trace at all.

### Manual install

* `vendor/SHA256SUMS` now clearly documents that the hashes verify the shipped
  binaries, not their provenance.
* Documented why locally rebuilt Windows binaries don't have the same hashes as
  the vendored copies.
* Pinned the documented Ignition source and patches to `6bb3c8a`.

---

## v1.0.0

First major release.

> `testing/rc` is the maintained branch.

* Removed the old `./standable gui` command and desktop entry. Use the Steam
  launch hook instead.
* The launch hook now clears SteamVR Safe Mode block markers when the game
  starts.
* `./standable check` reports Safe Mode block markers.
* Made the wineserver cleanup much faster by avoiding a full `/proc` environment
  scan for every Wine process.
* Added `server.out` logging for `ignition_server.exe`.
* Old `.bak` files are now cleaned up, keeping only the newest two per file.
* SteamVR Safe Mode blocks are cleared properly between sessions.
* Proton is resolved at runtime, using the prefix and Steam's configured Proton
  before falling back to the install-time version.
* Switching Proton now cleans up leftover processes from the previous build.
* Cleanup is limited to the Standable prefix so other games are left alone.
* The launch hook now runs Standable directly through Proton instead of chaining
  Steam's `%command%`.
* `steam_api64.dll` is now installed beside the Windows driver in both
  `bin/win64/` and `bin/linux64/`.
* Added a Python 3 shim for SteamVR's Sniper runtime. This fixes Proton launchers
  that require a newer Python version.
* Added `win_vrpath.sh` to keep the Windows-side driver path in sync with the
  currently selected Proton.
* Fixed the SteamVR error 301 / `load_drivers` crash caused by leftover
  wineservers.
* Added the RPC timeout mechanism so a stuck game driver cannot hang SteamVR
  indefinitely. The driver handshake and shutdown call sites were added later
  (see Unreleased).

---

## v0.1.2

* Standable can now be installed on any Steam library drive.
* The installer finds the game through Steam's `libraryfolders.vdf` instead of
  assuming the default Steam library.

---

## v0.1.1

* Fixed fresh-install SteamVR crashes caused by the missing
  `steam_api64.dll` Steamworks runtime.
* `./standable check` now verifies that `steam_api64.dll` is installed.
* Added `steam_api64.dll` to `vendor/SHA256SUMS`.
* Documented the source of the Steamworks DLL in `MANUAL.md`.

---

## v0.1.0

* Added the `Ignition` binaries directly to the project, so installing no
  longer requires a separate Ignition install.
* The installer detects which `s:` path convention the selected Proton uses.
* The launch scripts recreate the `s:` link if Proton removes it.
* Added the `./standable` command with `install`, `check`, and `uninstall`.
* Added a clear error for Flatpak Steam.
* Added a glibc compatibility check for the Linux driver.
* Added `vendor/SHA256SUMS`.
* Added `MANUAL.md` with manual installation and build instructions.
