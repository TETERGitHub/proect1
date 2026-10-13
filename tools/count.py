#!/usr/bin/env python3
"""Count source lines: total, non-blank, and 'content' (non-blank, non-comment)."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
rows = []
for group in ("src", "tests", "tools"):
    for p in sorted((ROOT / group).rglob("*")):
        if p.suffix not in (".luau", ".py"):
            continue
        total = blank = comment = 0
        in_block = False
        for line in p.read_text(encoding="utf-8").splitlines():
            total += 1
            s = line.strip()
            if not s:
                blank += 1
            elif p.suffix == ".luau" and (s.startswith("--")):
                comment += 1
            elif p.suffix == ".py" and s.startswith("#"):
                comment += 1
        rows.append((str(p.relative_to(ROOT)), total, total - blank - comment))
w = max(len(r[0]) for r in rows)
for name, total, content in rows:
    print(f"{name:<{w}}  total={total:>5}  content={content:>5}")
print("-" * (w + 28))
for group in ("src", "tests", "tools"):
    t = sum(r[1] for r in rows if r[0].startswith(group + "/"))
    c = sum(r[2] for r in rows if r[0].startswith(group + "/"))
    print(f"{group:<{w}}  total={t:>5}  content={c:>5}")
print(f"{'ALL':<{w}}  total={sum(r[1] for r in rows):>5}  content={sum(r[2] for r in rows):>5}")
