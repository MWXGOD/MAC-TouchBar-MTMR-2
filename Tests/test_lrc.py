import importlib.util
import pathlib

path = pathlib.Path(__file__).parents[1] / "Scripts" / "touchbar-lyrics-agent.py"
spec = importlib.util.spec_from_file_location("touchbar_agent", path)
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)

lines = agent.parse_lrc("[ti:Demo]\n[00:01.20]first\n[00:02.500][00:03]second")
assert lines == [(1.2, "first"), (2.5, "second"), (3.0, "second")]
assert agent.current_line(0.9, lines) is None
assert agent.current_line(2.7, lines) == "second"
print("LRC tests passed")
