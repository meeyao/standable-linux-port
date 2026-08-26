# Changelog

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
