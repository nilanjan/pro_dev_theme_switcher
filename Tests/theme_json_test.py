#!/usr/bin/env python3
# Validates every shipped Claude Code theme. Claude Code's loader silently drops
# overrides whose key is not in the base theme and whose value fails its colour
# regex, so a typo here does not error -- it just quietly does nothing. That is
# exactly the failure this catches.
import json, pathlib, re, sys

HEX = re.compile(r"^#[0-9a-fA-F]{6}$")
BASES = {"light", "dark", "light-daltonized", "dark-daltonized", "light-ansi", "dark-ansi"}
MIN_OVERRIDES = 50

bad = 0
for f in sorted(pathlib.Path("config/themes").glob("*/claude.json")):
    try:
        d = json.loads(f.read_text())
    except json.JSONDecodeError as e:
        print(f"  \033[31m✗\033[0m {f}: invalid JSON -- {e}")
        bad = 1
        continue

    problems = []
    if d.get("base") not in BASES:
        problems.append(f"base {d.get('base')!r} is not one of {sorted(BASES)}")
    if not isinstance(d.get("name"), str) or not d["name"]:
        problems.append("name missing or empty")

    ov = d.get("overrides")
    if not isinstance(ov, dict):
        problems.append("overrides missing")
    else:
        if len(ov) < MIN_OVERRIDES:
            problems.append(f"only {len(ov)} overrides, expected >= {MIN_OVERRIDES}")
        for k, v in sorted(ov.items()):
            if not isinstance(v, str) or not HEX.match(v):
                problems.append(f"{k} = {v!r} is not #rrggbb")

    # The slug is the filename Claude Code loads and the value sync.sh writes as
    # custom:<slug>; the directory name is the only thing tying them together.
    slug = f.parent.name
    mode = "dark" if d.get("base") == "dark" else "light"
    meta = (f.parent / "meta").read_text()
    meta_mode = next((l.split("=", 1)[1] for l in meta.splitlines()
                      if l.startswith("mode=")), None)
    if meta_mode != mode:
        problems.append(f"base {d.get('base')!r} disagrees with meta mode={meta_mode!r}")

    if problems:
        bad = 1
        for p in problems:
            print(f"  \033[31m✗\033[0m {slug}: {p}")
    else:
        print(f"  \033[32m✓\033[0m {slug}: base {d['base']}, {len(ov)} overrides, all #rrggbb")

sys.exit(bad)
