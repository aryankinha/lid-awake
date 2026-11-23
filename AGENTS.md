# LidAwake workflow

After every completed change, run `swift test` and `./scripts/build.sh` from the repository root. Update the existing `~/Applications/LidAwake.app` from the verified `dist/LidAwake.app`, refresh its bundled watchdog, and launch the installed copy. Verify the installed executable matches the build and the running process uses the installed path.

Before replacing the bundle, check that there is no active LidAwake session or pending sleep recovery. Preserve a previous bundle for rollback and quit any existing LidAwake process cleanly. If a session is active, leave it running and flag the pending installation. Keep source edits in the repository.
