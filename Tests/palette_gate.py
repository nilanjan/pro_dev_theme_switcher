#!/usr/bin/env python3
# Contrast and surface gate for every shipped theme. Split out of check.sh so CI can
# run it: it reads config/themes/ only and needs no app, no GUI and no appearance
# flipping. check.sh runs it too, so there is one copy of the rules.
import re, pathlib, sys
HOME = pathlib.Path.home()

def luma(h):
    h = h.lstrip("#"); r, g, b = (int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)

def cr(a, b):
    la, lb = luma(a), luma(b); hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

def field(text, section, key):
    m = re.search(rf"\[{section}\][^\[]*?\n\s*{key}\s*=\s*.#(\w{{6}})", text)
    return "#" + m.group(1) if m else None

bad = 0
def row(good, label, detail):
    global bad
    bad |= (not good)
    mark = "\033[32m✓\033[0m" if good else "\033[31m✗\033[0m"
    print(f"  {mark} {label:<22} {detail}")

# Light is held to 3:1 because Dawn's gold/rose/foam were corrected to reach it.
# Dark stays at 2:1: Storm's ANSI 0 is Storm's own comment grey (#565f89, 2.35:1),
# left canonical on purpose -- raising it would repaint every TUI's dim text.
THRESHOLD = {"light": 3.0, "dark": 2.0}

for mode in ("dark", "light"):
    # Gate the shipped theme, not ~/.config -- the live config only ever holds one
    # mode, so checking it would pass vacuously whenever the machine sits in the
    # other one. The default theme for each mode is the one under test.
    slug = "tokyo-night-storm" if mode == "dark" else "rose-pine-dawn"
    tdir = pathlib.Path("config/themes") / slug
    # Themes are self-contained: no import to resolve, so this works on any
    # checkout. It used to follow the upstream import into ~/.config, which meant
    # the gate could only run on a machine that had that themes repo cloned.
    ov = (tdir / "alacritty.toml").read_text()
    bg = field(ov, r"colors\.primary", "background")
    assert bg, f"{slug}: no colors.primary background"
    need = THRESHOLD[mode]
    print(f"-- {mode}: canvas {bg}, ANSI floor {need}:1")

    # ANSI 0-6 are text at some point -- TUIs draw bullets, box-drawing and dim text
    # with ANSI 0 -- so they must stay legible on the canvas.
    for name in ("black", "red", "green", "yellow", "blue", "magenta", "cyan"):
        c = field(ov, r"colors\.normal", name)
        r = cr(bg, c)
        row(r >= need, f"ansi {name}", f"{c} vs {bg} = {r:.2f}:1")

    # ANSI 7/15 carry the light end of the ramp in a light theme, so they are gated
    # as surfaces rather than as text; 0/8 carry the dark end and body text comes
    # from primary.foreground. In dark mode the roles swap and 7/15 are genuinely
    # text, so the text rule applies there instead.
    for sect, name, label in ((r"colors\.normal", "white", "ansi white"),
                              (r"colors\.bright", "white", "ansi whiteBright")):
        c = field(ov, sect, name)
        if mode == "light":
            row(luma(c) <= luma(bg) + 1e-9, label, f"{c} at or below canvas (surface)")
        else:
            r = cr(bg, c)
            row(r >= need, label, f"{c} vs {bg} = {r:.2f}:1")

    # A light theme has no headroom above its canvas: any surface lighter than it
    # reads as an unthemed white island (this is what the pane gaps, dividers and
    # the selected sidebar row were doing). Dark mode is exempt -- it has room on
    # both sides, and Storm deliberately recedes its chrome below the canvas.
    # Read the shipped block, not ~/.config/herdr/config.toml -- the live config
    # only ever holds one mode, so checking it would pass vacuously whenever the
    # machine happens to be sitting in the other one.
    blk = (tdir / "herdr.toml").read_text()
    tok = lambda name: (re.search(rf'^{name}\s*=\s*"(#\w{{6}})"', blk, re.M) or [None, None])[1]

    # The active pane border is [ui] accent, the inactive one is overlay0. Nothing
    # else asserts they differ, and they have collapsed once already: overlay0 was
    # left at #575279 by a since-abandoned attempt to recolour the tab-chip label,
    # which made every border look active. Relational, so no single value catches it.
    active = re.search(r"^accent=(#\w{6})", (tdir / "meta").read_text(), re.M).group(1)
    inactive = tok("overlay0")
    sep = cr(active, inactive)
    row(sep >= 2.0, "border separation",
        f"active {active} vs inactive {inactive} = {sep:.2f}:1 (need >=2.0)")

    if mode == "light":
        # All four are backgrounds; the accent-chip label is overlay0, not one of
        # these, so none of them has a reason to sit above the canvas.
        for tok in ("panel_bg", "surface0", "surface1", "surface_dim"):
            m = re.search(rf'^{tok}\s*=\s*"(#\w{{6}})"', blk, re.M)
            row(bool(m) and luma(m.group(1)) <= luma(bg) + 1e-9,
                f"surface {tok}",
                f"{m.group(1)} at or below canvas" if m else "MISSING from herdr.toml")

sys.exit(bad)
