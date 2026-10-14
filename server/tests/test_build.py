"""Module-loader semantics of the generated bundle (the HEADER in tools/build.py), run on the Luau CLI.
Skipped when no `luau` executable is available (set LUAU to its path)."""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import build  # noqa: E402

LUAU = os.environ.get("LUAU") or shutil.which("luau") or ("/tmp/claude-0/luau/luau" if os.path.exists("/tmp/claude-0/luau/luau") else None)


def run_lua(body: str) -> str:
    script = build.HEADER + body
    with tempfile.TemporaryDirectory() as d:
        path = pathlib.Path(d) / "t.lua"
        path.write_text(script, encoding="utf-8")
        res = subprocess.run([LUAU, str(path)], capture_output=True, text=True, timeout=60)
    if res.returncode != 0:
        raise AssertionError(res.stdout + res.stderr)
    return res.stdout.strip()


@unittest.skipUnless(LUAU, "luau CLI not available")
class ModuleLoader(unittest.TestCase):
    def test_failed_module_can_be_retried(self):
        out = run_lua('''
local fixed = false
__modules["bad"] = function() if not fixed then error("boom") end return "ok" end
local ok1, e1 = pcall(__import, "bad")
fixed = true
local ok2, v2 = pcall(__import, "bad")
print(ok1, tostring(e1):find("boom", 1, true) ~= nil, tostring(e1):find("circular", 1, true) == nil, ok2, v2)
''')
        self.assertEqual(out, "false\ttrue\ttrue\ttrue\tok")

    def test_circular_import_is_reported_and_state_stays_clean(self):
        out = run_lua('''
__modules["a"] = function(import) return import("b") end
__modules["b"] = function(import) return import("a") end
local ok, e = pcall(__import, "a")
local ok2, e2 = pcall(__import, "a")
print(ok, tostring(e):find("circular import", 1, true) ~= nil, ok2, tostring(e2):find("circular import", 1, true) ~= nil)
''')
        self.assertEqual(out, "false\ttrue\tfalse\ttrue")

    def test_results_are_cached_and_nil_becomes_true(self):
        out = run_lua('''
local n = 0
__modules["m"] = function() n += 1 return {} end
__modules["z"] = function() n += 10 end
print(__import("m") == __import("m"), __import("z"), __import("z"), n)
''')
        self.assertEqual(out, "true\ttrue\ttrue\t11")

    def test_unknown_module_is_named(self):
        out = run_lua('local ok, e = pcall(__import, "nope") print(ok, tostring(e):find("module not found: nope", 1, true) ~= nil)')
        self.assertEqual(out, "false\ttrue")


class BuildReproducibility(unittest.TestCase):
    """No Luau CLI needed: these check the generator itself."""

    def read(self, path):
        return pathlib.Path(path).read_bytes()

    def test_two_builds_are_byte_identical(self):
        a = self.read(build.build(False))
        b = self.read(build.build(False))
        self.assertEqual(a, b)
        a = self.read(build.build_loader("https://example.invalid"))
        b = self.read(build.build_loader("https://example.invalid"))
        self.assertEqual(a, b)

    def test_module_order_is_stable_and_sorted(self):
        names = list(build.collect(ROOT / "src"))
        self.assertEqual(names, sorted(names))

    def test_every_static_import_resolves_to_a_source_file(self):
        import re
        mods = build.collect(ROOT / "src")
        for name, src in mods.items():
            for target in re.findall(r'import\("([^"]+)"\)', src):
                self.assertIn(target, mods, f"{name} imports missing module {target}")
        loader = build.collect(ROOT / "loader", "loader/")
        for name, src in loader.items():
            for target in re.findall(r'import\("([^"]+)"\)', src):
                self.assertTrue(target in mods or target in loader, f"{name} imports missing module {target}")

    def test_loader_build_contains_no_secret_and_substitutes_the_url(self):
        text = self.read(build.build_loader("https://example.invalid")).decode()
        self.assertIn("https://example.invalid", text)
        self.assertNotIn("@@SERVER_URL@@", text)
        for forbidden in ("LICENSE_SECRET", "app/Hub", "features/Training"):
            self.assertNotIn(forbidden, text)

    def test_a_changed_source_changes_the_output(self):
        original = build.collect

        def patched(base, prefix=""):
            mods = original(base, prefix)
            if "core/Codec" in mods:
                mods["core/Codec"] += "\n-- changed"
            return mods

        before = self.read(build.build(False))
        build.collect = patched
        try:
            after = self.read(build.build(False))
        finally:
            build.collect = original
        self.assertNotEqual(before, after)
        self.assertEqual(before, self.read(build.build(False)))

    def test_plain_build_has_no_embedded_secret(self):
        text = self.read(build.build(False)).decode()
        self.assertIn("@@LICENSE_SECRET_HEX@@", text)  # still the placeholder: nothing secret in a plain build


if __name__ == "__main__":
    unittest.main()
