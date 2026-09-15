# MAC-TouchBar-MTMR-2

MTMR-main is a macOS Touch Bar utility for NetEase Cloud Music. It keeps the
Touch Bar visible across applications and provides centered lyrics, previous,
play/pause and next controls, the native macOS Control Strip, and a menu-bar
icon for the background app.

The included `MTMR-2.app` is a prebuilt release for Apple Silicon Macs. The
source code, build scripts, lyric agent, tests, and application bundle are all
included in this repository.

## Requirements

- macOS 11 or newer;
- a Mac with a Touch Bar;
- Apple Silicon;
- NetEase Cloud Music with MediaRemote metadata available;
- Xcode Command Line Tools;
- Homebrew is recommended for installing MTMR.

## Quick Start: Use the Prebuilt App

From the repository root, install the lyric-agent dependencies and register
the background agent:

```sh
./Scripts/install-dependencies.sh
./Scripts/build-agent.sh
./Scripts/install-launch-agent.sh
open ./MTMR-2.app
```

You can also copy the app to `/Applications`:

```sh
cp -R MTMR-2.app /Applications/
open /Applications/MTMR-2.app
```

Grant Accessibility permission if macOS requests it. Start NetEase Cloud
Music and play a song. The Touch Bar will show the centered lyric and the
three media controls; the native Control Strip remains on the right.

`install-mtmr-preset.sh` is optional. It installs the legacy MTMR preset and
is not required when using the included native `MTMR-2.app`.

## Build From Source

The native app build requires the MediaRemote command helper produced by
`install-dependencies.sh`:

```sh
./Scripts/install-dependencies.sh
./Scripts/build-agent.sh
./Scripts/build-native-touchbar.sh
open ./build/native-touchbar/MTMR-2.app
```

The build output is created under `build/native-touchbar/`. The app is
ad-hoc signed for local use; distribution outside the developer's Mac may
require signing and notarization.

## Tests and Diagnostics

```sh
./Scripts/test-lrc.sh
python3 Tests/test_lrc.py
python3 Tests/test_agent.py
./Scripts/build-ax-probe.sh
./build/ax-touchbar-probe --bundle com.ahs.mtmr2 --depth 8 --json
```

To verify the three native buttons through Accessibility:

```sh
./build/ax-touchbar-probe --bundle com.ahs.mtmr2 --depth 8 --json
```

Lyrics and state are stored under:

```text
~/Library/Application Support/TouchBarLyrics-MTMR-2/
```

The LaunchAgent log is stored at:
`~/Library/Logs/touchbarlyrics-mtmr2.log`.

## Project Layout

- `Sources/NativeTouchBarController.m`: native Touch Bar app and menu-bar item;
- `Scripts/touchbar-lyrics-agent.py`: MediaRemote and LRC lyric agent;
- `MTMR/items.json`: MTMR preset template;
- `LaunchAgents/`: background agent template;
- `Tests/`: lyric parser and agent behavior tests;
- `MTMR-2.app/`: prebuilt application bundle.

## Troubleshooting

- If lyrics are blank, confirm NetEase Cloud Music is playing and check
  `~/Library/Application Support/TouchBarLyrics-MTMR-2/display.txt`.
- If the agent is not running, inspect
  `~/Library/Logs/touchbarlyrics-mtmr2.log` and rerun
  `./Scripts/install-launch-agent.sh`.
- If the buttons do not respond, confirm that the app is running from the
  current build and that macOS Accessibility permission is enabled.
- If `install-dependencies.sh` cannot install MTMR, install MTMR manually
  from its official release and then run the remaining project scripts.

## Notes

The app uses private macOS Touch Bar APIs to present a system-modal Touch Bar
and add the native Control Strip. These APIs are version-dependent and may
change in future macOS releases.
