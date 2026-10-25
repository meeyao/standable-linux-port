# Standable FBE on Linux

**As of October 25, 2026, Standable works on Linux on the Steam beta branch
`open-beta` (build `26194383`, version `3.1.0 BETA 1`).** It has a native
SteamVR driver, and the Standable GUI runs through Proton. Install
[Standable on Steam](https://store.steampowered.com/app/2370570/), opt into the
`open-beta` beta under **Properties → Betas**, and launch it normally. You
don't need this patch.

The only thing I'm still working on is the
[WiVRn port](https://github.com/meeyao/standable-wivrn-port).

So this repo is done. I'm leaving it up because people still land here from old
links, and because some of you still need to get the patch off your machine.
Thanks to everyone in the Standable community and
[Discord](https://discord.gg/WPS2rWNJxG) for testing it, reporting bugs, and
putting up with the rough edges. It was a fun thing to build.

## Moving to the official Standable build

If you used the old patch and want to switch to the official Standable Linux
build, do this:

1. Quit SteamVR.
2. Clone the repo and run the uninstaller:

   ```sh
   git clone https://github.com/meeyao/standable-linux-port.git
   cd standable-linux-port
   ./install.sh --uninstall
   ```

3. In Steam, open **Standable → Properties → Installed Files → Verify
   integrity of game files**.
4. Make sure you're on the `open-beta` beta under **Properties → Betas**, then
   launch Standable.

The uninstaller takes out the old shim and helpers, puts back any files it
replaced, and leaves the things the official build needs alone: the driver, its
OpenVR entry, Proton's vrclient files, and your Steam settings.

Verify integrity is usually enough. If Standable still acts strange, reinstall
it. That deletes Standable's install folder, including `saves/`, so back that
up first if you care about your settings.

## Branches

- `testing/rc`: this page, and the uninstaller.
- [`ignition`](https://github.com/meeyao/standable-linux-port/tree/ignition):
  the old pre-beta code. Only use it if you are still on the pre-beta
  Standable build.

The old install guide is still at
[`a377535`](https://github.com/meeyao/standable-linux-port/blob/a377535/README.md).
It describes a version that doesn't match the current Standable build, so
don't follow it.

## License

MIT. See [LICENSE](LICENSE).
