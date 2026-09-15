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
    key = "Song\x1fArtist"
    instance.lyric_key = key
    instance.lyrics = [(0.0, "hello"), (10.0, "world")]
    instance.update({
        "title": "Song",
        "artist": "Artist",
        "elapsed": 1.0,
        "duration": 100.0,
        "rate": 1.0,
        "bundle": agent.NETEASE_BUNDLE,
    })
    assert read(agent.DISPLAY) == "hello"
    assert "Song" not in read(agent.DISPLAY)
    assert "Artist" not in read(agent.DISPLAY)

    instance.lyric_key = "Other\x1fArtist"
    instance.lyrics = []
    instance.lyrics_fetching.add(instance.lyric_key)
    instance.update({
        "title": "Other",
        "artist": "Artist",
        "elapsed": 1.0,
        "duration": 100.0,
        "rate": 1.0,
        "bundle": agent.NETEASE_BUNDLE,
    })
    assert read(agent.DISPLAY) == ""
    assert "error" not in read(agent.DISPLAY).lower()

print("agent behavior tests passed")
