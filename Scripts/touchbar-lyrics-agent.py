#!/usr/bin/env python3
"""Background NetEase now-playing -> LRC -> MTMR display bridge."""

import json
import os
import re
import select
import subprocess
import sys
import tempfile
import threading
import time
import unicodedata
import urllib.parse
import urllib.request

NETEASE_BUNDLE = "com.netease.163music"
ROOT = os.path.expanduser("~/Library/Application Support/TouchBarLyrics-MTMR-2")
DISPLAY = os.path.join(ROOT, "display.txt")
STATE = os.path.join(ROOT, "state.json")
CACHE = os.path.join(ROOT, "lyrics-cache.json")
TIME_RE = re.compile(r"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]")
RENDER_INTERVAL = 0.02
FALLBACK_INTERVAL = 1.0


def atomic_write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path, encoding="utf-8") as handle:
            if handle.read() == content:
                return
    except OSError:
        pass
    fd, temporary = tempfile.mkstemp(prefix=".touchbar-", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def parse_lrc(text):
    result = []
    for raw_line in text.splitlines():
        matches = list(TIME_RE.finditer(raw_line))
        if not matches:
            continue
        lyric = raw_line[matches[-1].end():].strip()
        for match in matches:
            fraction = match.group(3) or "0"
            result.append((int(match.group(1)) * 60 + int(match.group(2)) + int(fraction) / (10 ** len(fraction)), lyric))
    return sorted(result, key=lambda item: (item[0], item[1]))


def current_line(seconds, lines):
    selected = None
    for timestamp, lyric in lines:
        if timestamp > seconds:
            break
        if lyric:
            selected = lyric
    return selected


def match_key(value):
    normalized = unicodedata.normalize("NFKC", str(value or "")).casefold()
    return "".join(character for character in normalized if character.isalnum())


def playback_key(playback):
    # Duration separates remasters, live recordings, and special editions that
    # share the same title and artist metadata.
    duration = number(playback.get("duration"))
    duration_key = str(int(round(duration))) if duration > 0 else "unknown"
    return "\x1f".join((playback["title"], playback["artist"], duration_key))


def choose_song(songs, playback):
    title_key = match_key(playback["title"])
    artist_key = match_key(playback["artist"])
    target_duration = number(playback.get("duration"))
    ranked = []
    for index, song in enumerate(songs):
        name_exact = match_key(song.get("name")) == title_key
        artists = [match_key(artist.get("name")) for artist in song.get("artists", [])]
        artist_exact = not artist_key or artist_key in artists
        song_duration = number(song.get("duration")) / 1000.0
        duration_delta = (
            abs(song_duration - target_duration)
            if target_duration > 0 and song_duration > 0
            else float("inf")
        )
        ranked.append((
            0 if name_exact else 1,
            0 if artist_exact else 1,
            duration_delta,
            index,
            song,
        ))
    ranked.sort(key=lambda item: item[:-1])
    return ranked[0][-1] if ranked else None


class Agent:
    def __init__(self, helper):
        self.helper = helper
        self.watcher = None
        self.watcher_script = None
        self.watcher_dylib = None
        self.cache = {}
        self.lyrics = []
        self.lyric_key = None
        self.lyrics_fetching = set()
        self.lyrics_lock = threading.Lock()
        self.progress_key = None
        self.progress = 0.0
        self.last_raw_elapsed = None
        self.last_rate = 0.0
        self.last_progress_time = None
        self.progress_anchor = None
        self.progress_anchor_time = None
        self.latest_playback = None
        self.playback_lock = threading.Lock()
        self.event_serial = 0
        self.applied_event_serial = -1
        self.last_event_time = 0.0
        self.stop_event = threading.Event()
        self.last_display = None
        self.last_state = None
        self.last_state_write = 0.0
        try:
            with open(CACHE, encoding="utf-8") as handle:
                self.cache = json.load(handle)
        except (OSError, ValueError):
            pass

    def helper_json(self, arguments):
        try:
            environment = os.environ.copy()
            environment["MEDIAREMOTEADAPTER_OPTION_now"] = "1"
            environment["MEDIAREMOTEADAPTER_OPTION_minimal"] = "1"
            result = subprocess.run(
                [self.helper] + arguments,
                capture_output=True,
                text=True,
                timeout=3,
                env=environment,
            )
            if result.returncode:
                return None
            return json.loads(result.stdout)
        except (OSError, subprocess.SubprocessError, ValueError):
            return None

    def watcher_paths(self):
        executable_dir = os.path.dirname(os.path.realpath(self.helper))
        candidates = [
            (
                os.path.join(executable_dir, "scripts", "mediaremote-mini.pl"),
                os.path.join(executable_dir, "build", "mediaremote-mini", "MediaRemoteMini.dylib"),
            ),
            (
                os.path.join(executable_dir, "share", "nowplaying-cli", "scripts", "mediaremote-mini.pl"),
                os.path.join(executable_dir, "lib", "nowplaying-cli", "MediaRemoteMini.dylib"),
            ),
        ]
        for script, dylib in candidates:
            if os.access(script, os.R_OK) and os.access(dylib, os.R_OK):
                return script, dylib
        return None, None

    def start_watcher(self):
        if self.watcher and self.watcher.poll() is None:
            return True
        self.stop_watcher()
        script, dylib = self.watcher_paths()
        if not script:
            return False
        environment = os.environ.copy()
        environment["MEDIAREMOTEADAPTER_OPTION_now"] = "1"
        environment["MEDIAREMOTEADAPTER_OPTION_minimal"] = "1"
        try:
            self.watcher = subprocess.Popen(
                ["/usr/bin/perl", script, dylib, "adapter_watch_env"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
                text=False,
                bufsize=0,
                env=environment,
            )
            self.watcher_script = script
            self.watcher_dylib = dylib
            return True
        except (OSError, subprocess.SubprocessError):
            self.watcher = None
            return False

    def stop_watcher(self):
        if not self.watcher:
            return
        if self.watcher.poll() is None:
            self.watcher.terminate()
            try:
                self.watcher.wait(timeout=1)
            except subprocess.TimeoutExpired:
                self.watcher.kill()
                self.watcher.wait()
        if self.watcher.stdout:
            self.watcher.stdout.close()
        self.watcher = None

    def watcher_json(self):
        if not self.start_watcher() or not self.watcher or not self.watcher.stdout:
            return None
        try:
            ready, _, _ = select.select([self.watcher.stdout], [], [], 1.0)
            if not ready:
                self.stop_watcher()
                return None
            line = self.watcher.stdout.readline()
            if not line:
                self.stop_watcher()
                return None
            latest = json.loads(line)
            while True:
                ready, _, _ = select.select([self.watcher.stdout], [], [], 0)
                if not ready:
                    break
                line = self.watcher.stdout.readline()
                if not line:
                    break
                latest = json.loads(line)
            return latest
        except (OSError, ValueError, json.JSONDecodeError):
            self.stop_watcher()
            return None

    def normalize_playback(self, raw):
        if not raw:
            return None
        title = str(raw.get("title", "")).strip()
        bundle = str(raw.get("bundleIdentifier", "")).strip()
        if not title or bundle != NETEASE_BUNDLE:
            return None
        elapsed_now = raw.get("elapsedTimeNow")
        if not isinstance(elapsed_now, (int, float)):
            elapsed_now = raw.get("elapsedTime")
        return {
            "title": title,
            "artist": str(raw.get("artist", "")).strip(),
            "elapsed": number(elapsed_now),
            "duration": number(raw.get("duration")),
            "rate": number(raw.get("playbackRate")),
            "bundle": bundle,
        }

    def accept_playback(self, playback):
        with self.playback_lock:
            self.latest_playback = playback
            self.event_serial += 1
            self.last_event_time = time.monotonic()

    def helper_playback(self):
        return self.normalize_playback(self.helper_json([
            "get",
            "--json",
            "title",
            "artist",
            "duration",
            "elapsedTime",
            "elapsedTimeNow",
            "playbackRate",
            "bundleIdentifier",
        ]))

    def event_loop(self):
        """Consume MediaRemote events; use a slow snapshot only as a safety net."""
        self.start_watcher()
        next_fallback = 0.0
        while not self.stop_event.is_set():
            now = time.monotonic()
            if self.watcher and self.watcher.stdout and self.watcher.poll() is None:
                try:
                    ready, _, _ = select.select([self.watcher.stdout], [], [], 0.25)
                    if ready:
                        line = self.watcher.stdout.readline()
                        if not line:
                            self.stop_watcher()
                            continue
                        try:
                            self.accept_playback(self.normalize_playback(json.loads(line)))
                        except (ValueError, json.JSONDecodeError):
                            pass
                        # Drain already queued events so rendering uses the newest state.
                        while self.watcher and self.watcher.stdout:
                            ready, _, _ = select.select([self.watcher.stdout], [], [], 0)
                            if not ready:
                                break
                            line = self.watcher.stdout.readline()
                            if not line:
                                break
                            try:
                                self.accept_playback(self.normalize_playback(json.loads(line)))
                            except (ValueError, json.JSONDecodeError):
                                continue
                except (OSError, ValueError):
                    self.stop_watcher()
            else:
                self.stop_watcher()

            with self.playback_lock:
                last_event = self.last_event_time
            if now >= next_fallback and now - last_event >= FALLBACK_INTERVAL:
                snapshot = self.helper_playback()
                if snapshot is not None:
                    self.accept_playback(snapshot)
                next_fallback = now + FALLBACK_INTERVAL
            if not self.watcher:
                self.stop_event.wait(0.25)

    def progressed_playback(self, playback, serial):
        """Use fresh MediaRemote anchors and only extrapolate between events."""
        now = time.monotonic()
        key = playback_key(playback)
        raw_elapsed = max(0.0, playback["elapsed"])
        rate = max(0.0, playback["rate"])

        if serial != self.applied_event_serial:
            # elapsedTimeNow is already projected to the time the adapter
            # sampled MediaRemote. Re-anchoring every event prevents local
            # clock error from accumulating over the length of a song.
            self.progress_anchor = raw_elapsed
            self.progress_anchor_time = now
            self.progress_key = key
            self.last_rate = rate
            self.applied_event_serial = serial

        if self.progress_anchor is None or self.progress_anchor_time is None:
            self.progress_anchor = raw_elapsed
            self.progress_anchor_time = now
        self.progress = self.progress_anchor + max(0.0, now - self.progress_anchor_time) * self.last_rate
        self.progress = min(max(self.progress, 0.0), max(playback["duration"], 0.0) or self.progress)
        self.last_progress_time = now
        self.last_raw_elapsed = raw_elapsed
        playback = dict(playback)
        playback["elapsed"] = self.progress
        return playback

    def playback(self):
        return self.helper_playback()

    def request_json(self, url):
        request = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 TouchBarLyrics/1.0",
            "Referer": "https://music.163.com/",
        })
        try:
            with urllib.request.urlopen(request, timeout=8) as response:
                return json.loads(response.read().decode("utf-8"))
        except (OSError, ValueError):
            return None

    def fetch_lyrics(self, playback):
        query = " ".join(part for part in (playback["title"], playback["artist"]) if part)
        params = urllib.parse.urlencode({"type": "1", "limit": "10", "s": query})
        search = self.request_json("https://music.163.com/api/search/get/web?" + params)
        songs = ((search or {}).get("result") or {}).get("songs") or []
        chosen = choose_song(songs, playback)
        if not chosen or not chosen.get("id"):
            return []
        lyric_json = self.request_json("https://music.163.com/api/song/lyric?" + urllib.parse.urlencode({"id": chosen["id"], "lv": 1, "kv": 1, "tv": -1}))
        lyric = ((lyric_json or {}).get("lrc") or {}).get("lyric")
        return parse_lrc(lyric) if lyric else []

    def fetch_lyrics_async(self, playback, key):
        try:
            lyrics = self.fetch_lyrics(playback)
            with self.lyrics_lock:
                self.cache[key] = lyrics
                if key == self.lyric_key:
                    self.lyrics = lyrics
                self.lyrics_fetching.discard(key)
            atomic_write(CACHE, json.dumps(self.cache, ensure_ascii=False))
        except Exception:
            with self.lyrics_lock:
                self.lyrics_fetching.discard(key)

    def update(self, playback):
        if playback is None:
            if self.last_display != "":
                atomic_write(DISPLAY, "")
                self.last_display = ""
            empty_state = {
                "title": "",
                "artist": "",
                "elapsed": 0.0,
                "duration": 0.0,
                "rate": 0.0,
                "bundle": "",
                "playing": False,
                "line": "",
            }
            now = time.monotonic()
            state_key = json.dumps(empty_state, ensure_ascii=False, sort_keys=True)
            if state_key != self.last_state or now - self.last_state_write >= 0.1:
                atomic_write(STATE, json.dumps(empty_state, ensure_ascii=False))
                self.last_state = state_key
                self.last_state_write = now
            self.progress_key = None
            self.last_raw_elapsed = None
            self.last_rate = 0.0
            self.last_progress_time = None
            self.progress_anchor = None
            self.progress_anchor_time = None
            self.applied_event_serial = -1
            return

        playback = dict(playback)
        key = playback_key(playback)
        if key != self.lyric_key:
            self.lyric_key = key
            with self.lyrics_lock:
                self.lyrics = self.cache.get(key, [])
                should_fetch = not self.lyrics and key not in self.lyrics_fetching
                if should_fetch:
                    self.lyrics_fetching.add(key)
            if should_fetch:
                threading.Thread(
                    target=self.fetch_lyrics_async,
                    args=(playback, key),
                    daemon=True,
                ).start()
        # Keep an empty display while lyrics are unavailable; never expose an error string or title.
        line = current_line(playback["elapsed"], self.lyrics) or ""
        if line != self.last_display:
            atomic_write(DISPLAY, line)
            self.last_display = line
        state = dict(playback, playing=playback["rate"] > 0.01, line=line)

        now = time.monotonic()
        state_key = json.dumps(state, ensure_ascii=False, sort_keys=True)
        if state_key != self.last_state or now - self.last_state_write >= 0.1:
            atomic_write(STATE, json.dumps(state, ensure_ascii=False))
            self.last_state = state_key
            self.last_state_write = now

    def render(self):
        with self.playback_lock:
            playback = dict(self.latest_playback) if self.latest_playback else None
            serial = self.event_serial
        if playback is None:
            self.update(None)
            return
        self.update(self.progressed_playback(playback, serial))

    def run(self):
        event_thread = threading.Thread(target=self.event_loop, name="mediaremote-events", daemon=True)
        event_thread.start()
        try:
            while not self.stop_event.is_set():
                self.render()
                self.stop_event.wait(RENDER_INTERVAL)
        finally:
            self.stop_event.set()
            self.stop_watcher()


def helper_path():
    sibling = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "nowplaying-cli")
    return os.environ.get("NOWPLAYING_CLI", sibling if os.access(sibling, os.X_OK) else "/opt/homebrew/bin/nowplaying-cli")


def main():
    helper = helper_path()
    if len(sys.argv) >= 3 and sys.argv[1] == "--command":
        command = sys.argv[2]
        project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        apple_script = os.path.join(project_dir, "Scripts", "netease-media-command.applescript")
        if os.access(apple_script, os.R_OK):
            try:
                return subprocess.run(
                    ["/usr/bin/osascript", apple_script, command],
                    timeout=5,
                ).returncode
            except (OSError, subprocess.SubprocessError):
                return 1
        media_command = os.path.join(
            os.path.dirname(os.path.abspath(sys.argv[0])),
            "touchbar-media-command",
        )
        command_helper = media_command if os.access(media_command, os.X_OK) else helper
        command = "togglePlayPause" if command == "toggle" and command_helper == helper else command
        try:
            arguments = [command_helper, command]
            return subprocess.run(arguments, timeout=5).returncode
        except (OSError, subprocess.SubprocessError):
            return 1
    if len(sys.argv) >= 2 and sys.argv[1] == "--display":
        try:
            print(open(DISPLAY, encoding="utf-8").read(), end="")
        except OSError:
            pass
        return 0
    Agent(helper).run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
