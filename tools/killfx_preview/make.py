import sys, pathlib, subprocess
S = pathlib.Path(sys.argv[0]).resolve().parent
SRC = S.parent.parent / "src"
mods = "MODULES = {}\n" + "".join('MODULES["%s"] = function(...)\n%s\nend\n' % (m, (SRC / (m + ".luau")).read_text()) for m in ("features/FxKit", "features/KillFX", "features/AuraFX"))
LUAU = next((a for a in sys.argv[1:] if not a.startswith("--")), "/tmp/claude-0/luau/luau")
for name in ([] if "--auras" in sys.argv else ["Lightning", "Explosion", "Vaporize", "BlackHole", "Shatter", "Troll"]):
    if any(a.startswith("--only=") for a in sys.argv) and name not in next(a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--only=")):
        continue
    body = (S / "prelude.luau").read_text() + "\n" + mods + (S / "main.luau").read_text().replace("EFFECT_NAME", '"%s"' % name)
    f = S / ("run_%s.luau" % name)
    f.write_text(body)
    out = subprocess.run([LUAU, str(f)], capture_output=True, text=True)
    (S / ("%s.txt" % name)).write_text(out.stdout)
    frames = out.stdout.count("\nF ")
    print(name, "frames", frames, "lines", out.stdout.count("\n"), out.stderr[:400], [l for l in out.stdout.splitlines() if l.startswith("WARN")][:3])


AURAS = ["Inferno Crown", "Storm God", "Galaxy", "Frost Monarch", "Void Wings", "Sakura", "Phoenix", "Dragon Spirit", "Holy Light",
         "Toxic Rift", "Shadow Reaper", "Neon Cyber", "Troll", "Burning"]
ONLY = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--only=")), None)
if "--auras" in sys.argv:
    for name in AURAS:
        if ONLY and name not in ONLY:
            continue
        body = (S / "prelude.luau").read_text() + "\n" + mods + (S / "aura_main.luau").read_text().replace("EFFECT_NAME", '"%s"' % name)
        f = S / ("run_aura.luau")
        f.write_text(body)
        out = subprocess.run([LUAU, str(f)], capture_output=True, text=True)
        key = "aura_" + name.replace(" ", "")
        (S / (key + ".txt")).write_text(out.stdout)
        print(name, "frames", out.stdout.count("\nF "), out.stderr[:300], [l for l in out.stdout.splitlines() if l.startswith("WARN")][:2])
