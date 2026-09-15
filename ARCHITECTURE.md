# MTMR-main Architecture

MTMR-main is an independent project with its own lyric data directory,
preset installation flow, LaunchAgent label, and source tree. The native app
binary remains named MTMR-2 for compatibility with the current release.

## Goal

Mirror the NetEase Cloud Music native Touch Bar experience while keeping it
visible when another application is frontmost, with playback controls and
lyric timing that feel native.

## Low-latency path

The resident agent consumes MediaRemote events, loads LRC data only when the
track changes, and selects the current line from a monotonic local clock. It
retains the last valid line during temporary metadata or network failures, so
transient failures do not appear as visible `error` text.

The native Touch Bar app presents the controls, centered lyric view, menu-bar
icon, and system Control Strip. Playback commands are sent through
MediaRemote.

## Timing target

Track changes and play/pause are event-driven. Once a lyric timeline is
loaded, the displayed line is selected locally from the current playback
position instead of waiting for repeated network or shell calls.

## Compatibility

The native app uses private macOS Touch Bar APIs to present a system-modal bar
and add the Control Strip. These APIs are version-dependent and may change in
future macOS releases. Installing the LaunchAgent and MTMR preset remains an
explicit user action.
