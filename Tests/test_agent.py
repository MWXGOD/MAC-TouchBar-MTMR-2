import importlib.util
import pathlib
import tempfile


path = pathlib.Path(__file__).parents[1] / "Scripts" / "touchbar-lyrics-agent.py"
spec = importlib.util.spec_from_file_location("touchbar_agent", path)
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


def read(path):
    return pathlib.Path(path).read_text(encoding="utf-8")


with tempfile.TemporaryDirectory() as directory:
    agent.DISPLAY = str(pathlib.Path(directory) / "display.txt")
    agent.STATE = str(pathlib.Path(directory) / "state.json")
    agent.CACHE = str(pathlib.Path(directory) / "lyrics-cache.json")
    instance = agent.Agent("/does/not/exist")
    playback = {
        "title": "Song",
        "artist": "Artist",
        "elapsed": 1.0,
        "duration": 100.0,
        "rate": 1.0,
        "bundle": agent.NETEASE_BUNDLE,
    }
    key = agent.playback_key(playback)
    instance.lyric_key = key
    instance.lyrics = [(0.0, "hello"), (1.4, "not yet"), (10.0, "world")]
    instance.update(playback)
    assert read(agent.DISPLAY) == "hello"
    assert "Song" not in read(agent.DISPLAY)
    assert "Artist" not in read(agent.DISPLAY)

    instance.update(dict(playback, elapsed=1.0))
    assert read(agent.DISPLAY) == "hello"

    other = dict(playback, title="Other")
    instance.lyric_key = agent.playback_key(other)
    instance.lyrics = []
    instance.lyrics_fetching.add(instance.lyric_key)
    instance.update(other)
    assert read(agent.DISPLAY) == ""
    assert "error" not in read(agent.DISPLAY).lower()

print("agent behavior tests passed")


songs = [
    {"id": 1, "name": "千古", "duration": 220046, "artists": [{"name": "许嵩"}]},
    {"id": 2, "name": "千古", "duration": 221180, "artists": [{"name": "许嵩"}]},
]
chosen = agent.choose_song(songs, {
    "title": "千古",
    "artist": "许嵩",
    "duration": 221.24,
})
assert chosen["id"] == 2


clock = iter((100.0, 100.05, 100.10))
original_monotonic = agent.time.monotonic
agent.time.monotonic = lambda: next(clock)
try:
    instance = agent.Agent("/does/not/exist")
    sample = {
        "title": "Song",
        "artist": "Artist",
        "elapsed": 10.0,
        "duration": 100.0,
        "rate": 1.0,
        "bundle": agent.NETEASE_BUNDLE,
    }
    first = instance.progressed_playback(sample, 1)
    second = instance.progressed_playback(dict(sample, elapsed=10.02), 2)
    third = instance.progressed_playback(dict(sample, elapsed=10.04), 2)
    assert first["elapsed"] == 10.0
    assert second["elapsed"] == 10.02
    assert round(third["elapsed"], 2) == 10.07
finally:
    agent.time.monotonic = original_monotonic

print("timing and song matching tests passed")
