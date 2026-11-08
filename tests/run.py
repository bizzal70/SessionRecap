"""Runs the addon's tests in real Lua 5.1 against a fake WoW API.

Setup (once):  pip install lupa
Run:           python tests/run.py

The fake API (wow_stub.lua) only proves the addon's own logic. It says
nothing about whether the real client's API behaves the way the stub does.
"""
import pathlib
import sys

import lupa.lua51 as lua51

TESTS = pathlib.Path(__file__).resolve().parent
ADDON = TESTS.parent   # the addon's files sit at the top of the project

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.globals().ADDON_DIR = ADDON.as_posix()
lua.execute((TESTS / "wow_stub.lua").read_text(encoding="utf-8"))
try:
    lua.execute((TESTS / "test_sessionrecap.lua").read_text(encoding="utf-8"))
    print("test_sessionrecap.lua: ALL PASSED")
except Exception as error:
    print(f"test_sessionrecap.lua: ERROR: {error}")
    sys.exit(1)


# Texture paths in Lua strings need doubled backslashes ("Interface\\Icons\\X").
# Lua drops a single backslash without an error, so the path breaks and the
# texture never draws (ZoomPad 0.2.0-0.2.2 shipped an invisible minimap button
# this way). Fail the run if any addon file has one.
import re as _re
_single = _re.compile(r'"Interface\\[A-Za-z]')
_broken = []
for _file in sorted(ADDON.rglob("*.lua")):
    if "tests" in _file.relative_to(ADDON).parts:
        continue
    for _n, _line in enumerate(_file.read_text(encoding="utf-8").splitlines(), 1):
        if _single.search(_line):
            _broken.append(f"{_file.relative_to(ADDON)}:{_n}: {_line.strip()}")
if _broken:
    print("Texture paths with single backslashes (write them as \\\\):")
    for _entry in _broken:
        print("  " + _entry)
    sys.exit(1)
print("texture paths: OK")
