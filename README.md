# MAC-TouchBar-MTMR-2

MTMR-2 is a native macOS Touch Bar companion for NetEase Cloud Music. It keeps
centered, lyric-only text and a three-part media control on the Touch Bar while
you switch between apps. The native macOS Control Strip remains available.

This repository includes the Objective-C app source, the lyric agent and
install scripts, diagnostics, and a prebuilt Apple Silicon app bundle.

## Requirements

- A Mac with a Touch Bar running macOS 11 or newer.
- Apple Silicon for the included prebuilt app and dependency installer.
- The native NetEase Cloud Music macOS app (`com.netease.163music`).
- Accessibility permission for MTMR-2 to control NetEase's own media menu.
- Xcode Command Line Tools and Homebrew for building or installing the lyric
  agent dependencies.

## Install

From a checkout of this repository, install the MediaRemote reader and prepare
the lyric agent:

```sh
./Scripts/install-dependencies.sh
./Scripts/build-agent.sh
./Scripts/install-launch-agent.sh
```

The dependency script also attempts to install the legacy MTMR app through
Homebrew. That legacy preset is optional when using the included native
`MTMR-2.app`.

Copy and launch the prebuilt app:

```sh
ditto MTMR-2.app /Applications/MTMR-2.app
open /Applications/MTMR-2.app
```

In **System Settings > Privacy & Security > Accessibility**, enable
`/Applications/MTMR-2.app`. If macOS has remembered a previous copy of the
app, remove that old entry and add the app from `/Applications` again. Quit
and relaunch MTMR-2 after changing permission. The media buttons use this
permission to reach NetEase's own `控制` menu without bringing its window to
the foreground.

Start playing a song in NetEase Cloud Music. MTMR-2 displays the current lyric
line only; it does not display the track title or artist. Lyrics are supplied
by the background agent and refreshed by the app. The lyric timeline follows
the player's MediaRemote playback position; no fixed manual time offset is
applied.

## Touch Bar Controls

- **Previous, play/pause, next:** three independently clickable regions in one
  connected, rounded media-control component. The current layout is 50 x 30
  points per region, with the existing white glyphs and gray segmented
  background.
- **NetEase targeting:** commands first use NetEase's Accessibility menu.
  Targeted fallbacks are available for supported permission and player-state
  configurations. Commands are serialized, and generic media commands are
  not sent to Apple Music or another active player. The app compares playback
  state before and after each accepted command and records whether it changed.
- **Close and restore:** closing the system-modal Touch Bar hides the MTMR-2
  view. Its Control Strip item can bring the lyric Touch Bar back.
- **Logos:** the Touch Bar Control Strip uses the white-only MTMR mark; the
  menu-bar icon uses the original mark with rounded corners.
- **Native Control Strip:** remains part of the system Touch Bar and can be
  expanded using macOS's normal controls.
- **Screen sleep sync:** the menu-bar setting `屏幕休眠时同步触控栏` is enabled
  by default. It minimizes MTMR-2 when the display sleeps and restores it when
  the display wakes. The setting is remembered between launches.

The app uses private macOS Touch Bar APIs. Apple may change those APIs in a
future macOS version.

## Build From Source

On an Apple Silicon Mac with Xcode Command Line Tools and Homebrew:

```sh
./Scripts/install-dependencies.sh
./Scripts/build-agent.sh
./Scripts/build-native-touchbar.sh
open ./build/native-touchbar/MTMR-2.app
```

The native build script compiles the HID helper when needed and packages the
NetEase Touch Bar glyph assets and targeted AppleScript fallback into the app.
The result is ad-hoc signed for local use. GitHub's app bundle is an arm64
build and is not Developer ID signed or notarized; Gatekeeper may require
opening it from Finder after download.

To install the native app instead of running it from the build directory:

```sh
ditto ./build/native-touchbar/MTMR-2.app /Applications/MTMR-2.app
open /Applications/MTMR-2.app
```

## Tests and Diagnostics

```sh
./Scripts/test-lrc.sh
python3 Tests/test_lrc.py
python3 Tests/test_agent.py
./Scripts/build-ax-probe.sh
./build/ax-touchbar-probe --bundle com.ahs.mtmr2 --depth 8 --json
```

Lyrics and playback state are stored under:

```text
~/Library/Application Support/TouchBarLyrics-MTMR-2/
```

Useful files include `display.txt`, `state.json`, and `button-debug.log`. The
button log records the selected command path and whether playback state
changed, which helps distinguish a missed touch from a rejected player action.
The launch agent log is `~/Library/Logs/touchbarlyrics-mtmr2.log`.

## Project Layout

- `Sources/NativeTouchBarController.m`: native app, Touch Bar controls, and
  NetEase-targeted command routing;
- `Scripts/touchbar-lyrics-agent.py`: MediaRemote state and lyric agent;
- `Scripts/netease-media-command.applescript`: targeted UI-scripting fallback;
- `Assets/netease-touchbar/`: high-resolution media glyph assets;
- `MTMR-2.app/`: prebuilt app bundle;
- `Tests/`: lyric parser and agent tests.

## Troubleshooting

- **Buttons do nothing:** confirm Accessibility is enabled for the exact app
  at `/Applications/MTMR-2.app`, then quit and reopen MTMR-2. Check
  `button-debug.log` for command routing details. AppleScript fallback may
  also require allowing MTMR-2 to control System Events under **Privacy &
  Security > Automation**.
- **Lyrics are blank:** confirm NetEase is playing and inspect
  `display.txt`, `state.json`, and
  `~/Library/Logs/touchbarlyrics-mtmr2.log`.
- **The app does not appear on the Touch Bar:** confirm the Mac has a Touch Bar
  and relaunch MTMR-2. The app uses private system-modal Touch Bar APIs, which
  can vary across macOS releases.
- **The agent is not running:** rerun `./Scripts/install-launch-agent.sh` from
  this checkout and inspect its log. The launch agent references this
  checkout's `build/touchbar-lyrics-agent`, so keep the repository in place.

`Scripts/install-mtmr-preset.sh` installs the separate legacy MTMR preset. It
is not required by the included native app.
