# LidAwake

LidAwake is a menu bar app that keeps your MacBook awake when you close its lid. Use it for downloads, builds, or other tasks you want to finish in the background.

## Will it work on my Mac?

- **Apple silicon MacBook:** Tested on a MacBook Pro with an M3 chip running macOS 27.2.
- **Intel MacBook:** The Intel build passed automated tests on an Apple silicon Mac using Rosetta. Closing the lid on a physical Intel MacBook still needs testing.
- **macOS:** Requires macOS 13 Ventura or newer. Some MacBook models or macOS versions may still sleep with the lid closed.
- **Desktop Mac:** LidAwake is designed for MacBooks. A Mac without an internal battery cannot start a session.

## Download and install

There is no ready-made app on GitHub Releases yet. You can download the project and build it on your Mac.

1. Install [Xcode](https://apps.apple.com/app/xcode/id497799835) 16 or newer and open it once.
2. Open the [LidAwake project on GitHub](https://github.com/aryankinha/lid-awake). Click **Code → Download ZIP**.
3. Double-click the downloaded ZIP to extract it.
4. Open Terminal. Type `cd ` with a trailing space, drag the extracted folder into Terminal, and press Return.
5. Run:

   ```sh
   ./scripts/install.sh
   ```

6. Click the laptop icon in the menu bar. The installer puts LidAwake in the **Applications** folder inside your home folder and opens it for you.

To update, download the latest project and repeat steps 3–5. End any LidAwake session before running the installer.

## Use LidAwake

1. Open LidAwake from the menu bar.
2. Set the **Auto-stop timer** and **Battery limit**.
3. Click **Turn On**. The laptop icon changes and the panel shows how much time is left.
4. Close the lid after confirming the app is on. For your first test, run a small download or another task with no important work at risk, and check that it continues.
5. Click **Turn Off** to restore normal sleep. If **Stop when lid opens** is enabled, reopening the lid after closing it ends the session.

Sessions have an eight-hour cap. Keep the MacBook on a hard, ventilated surface when it runs with the lid closed. Avoid putting it in a bag while it is awake.

In **Advanced Settings**, you can enable temperature protection, open LidAwake at login, or open Diagnostics.

## If something goes wrong

- **The icon is missing:** Open LidAwake from your home folder’s Applications folder and check the menu bar.
- **You see a safety check warning:** Click **Repair** in the panel. Wait for the warning to clear before starting.
- **The Mac still sleeps with the lid closed:** Keep the lid open for important work. LidAwake’s default sleep control depends on the Mac and its macOS version. **All sleep** is an optional mode that needs administrator setup and affects sleep across the whole Mac. Details are in [Architecture](ARCHITECTURE.md).
- **You see an older interface:** Quit LidAwake, run the installer again, and open the copy in your home folder’s Applications folder.

## Remove LidAwake

1. Turn off any active session.
2. Open Terminal and run:

   ```sh
   ~/Applications/LidAwake.app/Contents/Resources/uninstall.sh
   ```

The uninstaller removes the app and its background safety helper. If you set up **All sleep**, macOS may ask for administrator approval to remove it.

## Build or test the project

- Run the automated tests with `swift test`.
- Build for your current Mac with `./scripts/build.sh`.
- Build one ZIP for both Apple silicon and Intel with `./scripts/build.sh --universal`. Find it at `dist/LidAwake-universal.zip`. This ZIP is for local testing. Public downloads should go through Apple’s signing and security checks so macOS can open them without extra warnings. [Apple’s distribution guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

See [Architecture](ARCHITECTURE.md), [Test results](TEST_RESULTS.md), and [License](LICENSE) for more detail.
