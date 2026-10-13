#!/usr/bin/env python3
"""Regenerate docs/FEATURES.md from the live feature registry using the Luau CLI."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import build  # noqa: E402

LUAU = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path("/tmp/claude-0/luau/luau")
out = build.build(True)
src = out.read_text(encoding="utf-8").replace('return __import("tests/runner")', 'return __import("tests/docgen")')
tmp = ROOT / "dist" / "docgen.lua"
tmp.write_text(src, encoding="utf-8")
proc = subprocess.run([str(LUAU), str(tmp)], capture_output=True, text=True)
if "BEGIN_DOC" not in proc.stdout:
    print(proc.stdout, proc.stderr)
    sys.exit(1)
doc = proc.stdout.split("BEGIN_DOC\n")[1].split("END_DOC")[0]
(ROOT / "docs" / "FEATURES.md").write_text(doc, encoding="utf-8")
print("wrote docs/FEATURES.md")
