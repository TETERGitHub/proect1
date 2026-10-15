import sys, pathlib, subprocess
S = pathlib.Path(sys.argv[0]).resolve().parent
src = (S.parent.parent / "src" / "features" / "KillFX.luau").read_text()
LUAU = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/luau/luau"
for name in ["Lightning", "Explosion", "Vaporize", "BlackHole", "Shatter"]:
    body = (S / "prelude.luau").read_text() + "\nlocal function KILLFX_MODULE(...)\n" + src + "\nend\n" + \
        (S / "main.luau").read_text().replace("EFFECT_NAME", '"%s"' % name)
    f = S / ("run_%s.luau" % name)
    f.write_text(body)
    out = subprocess.run([LUAU, str(f)], capture_output=True, text=True)
    (S / ("%s.txt" % name)).write_text(out.stdout)
    frames = out.stdout.count("\nF ")
    print(name, "frames", frames, "lines", out.stdout.count("\n"), out.stderr[:400], [l for l in out.stdout.splitlines() if l.startswith("WARN")][:3])
