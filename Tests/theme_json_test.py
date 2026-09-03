#!/usr/bin/env python3
# Validates every shipped Claude Code theme. Claude Code's loader silently drops
# overrides whose key is not in the base theme and whose value fails its colour
# regex, so a typo here does not error -- it just quietly does nothing. That is
# exactly the failure this catches.
import json, pathlib, re, sys

HEX = re.compile(r"^#[0-9a-fA-F]{6}$")
BASES = {"light", "dark", "light-daltonized", "dark-daltonized", "light-ansi", "dark-ansi"}
# Every key Claude Code's palette defines. A theme must set all of them: an omitted
# key is not an error, it just leaks that built-in theme's own colour through -- which
# is how the ultrathink rainbow, the ultracode label and the fast-mode indicator kept
# their stock hues while everything around them was themed. Read off the palette
# tables in the Claude Code binary; if a release adds a key, this list is where the
# gap shows up. Grep a version with:
#   LC_ALL=C grep -abo 'composerSidebarBackground:"' "$(readlink -f "$(which claude)")"
KEYS = {
    "autoAccept", "autoAcceptShimmer", "skill", "bashBorder", "claude", "claudeShimmer",
    "claudeBlue_FOR_SYSTEM_SPINNER", "claudeBlueShimmer_FOR_SYSTEM_SPINNER",
    "permission", "permissionShimmer", "planMode", "ide", "promptBorder",
    "promptBorderShimmer", "text", "inverseText", "inactive", "inactiveShimmer",
    "subtle", "suggestion", "remember", "background", "success", "error", "warning",
    "merged", "warningShimmer", "diffAdded", "diffRemoved", "diffAddedDimmed",
    "diffRemovedDimmed", "diffAddedWord", "diffRemovedWord", "professionalBlue",
    "chromeYellow", "clawd_body", "clawd_background", "userMessageBackground",
    "userMessageBackgroundHover", "composerSidebarBackground", "selectionBg",
    "bashMessageBackgroundColor", "memoryBackgroundColor", "rate_limit_fill",
    "rate_limit_empty", "fastMode", "fastModeShimmer", "effortUltra", "briefLabelYou",
    "briefLabelClaude",
} | {f"{c}_FOR_SUBAGENTS_ONLY" for c in
     ("red", "blue", "green", "yellow", "purple", "orange", "pink", "cyan")} \
  | {f"rainbow_{h}{s}" for s in ("", "_shimmer") for h in
     ("red", "orange", "yellow", "green", "blue", "indigo", "violet")}

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
        # Claude Code drops an unknown key without a word, so a typo is invisible
        # until someone notices one thing is the wrong colour.
        for k in sorted(set(ov) - KEYS):
            problems.append(f"{k} is not a Claude Code palette key (silently dropped)")
        for k in sorted(KEYS - set(ov)):
            problems.append(f"{k} missing (falls back to the built-in palette)")
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
        print(f"  \033[32m✓\033[0m {slug}: base {d['base']}, all {len(ov)} keys, all #rrggbb")

# --- OpenCode ------------------------------------------------------------------
# Same contract, different tool. OpenCode's resolver throws on an unknown colour
# reference but simply has no value for a token you leave out, so a partial theme
# is a half-themed UI. Read off packages/tui/src/theme/index.ts (type Theme);
# selectedListItemText and backgroundMenu have fallbacks, the rest do not -- we set
# all of them anyway, because a fallback is still a colour we did not choose.
OC_KEYS = {
    "primary", "secondary", "accent", "error", "warning", "success", "info",
    "text", "textMuted", "selectedListItemText",
    "background", "backgroundPanel", "backgroundElement", "backgroundMenu",
    "border", "borderActive", "borderSubtle",
    "diffAdded", "diffRemoved", "diffContext", "diffHunkHeader",
    "diffHighlightAdded", "diffHighlightRemoved",
    "diffAddedBg", "diffRemovedBg", "diffContextBg", "diffLineNumber",
    "diffAddedLineNumberBg", "diffRemovedLineNumberBg",
} | {f"markdown{k}" for k in
     ("Text", "Heading", "Link", "LinkText", "Code", "BlockQuote", "Emph", "Strong",
      "HorizontalRule", "ListItem", "ListEnumeration", "Image", "ImageText", "CodeBlock")} \
  | {f"syntax{k}" for k in
     ("Comment", "Keyword", "Function", "Variable", "String", "Number", "Type",
      "Operator", "Punctuation")}

for f in sorted(pathlib.Path("config/themes").glob("*/opencode.json")):
    slug = f.parent.name
    try:
        d = json.loads(f.read_text())
    except json.JSONDecodeError as e:
        print(f"  \033[31m✗\033[0m {slug}/opencode.json: invalid JSON -- {e}")
        bad = 1
        continue
    problems = []
    th = d.get("theme")
    if not isinstance(th, dict):
        problems.append("no 'theme' object")
    else:
        for k in sorted(set(th) - OC_KEYS):
            problems.append(f"{k} is not an OpenCode theme token")
        for k in sorted(OC_KEYS - set(th)):
            problems.append(f"{k} missing (OpenCode has no colour for it)")
        for k, v in sorted(th.items()):
            # Values are written flat, not as {"dark":…,"light":…} variants: the
            # switcher decides the mode, so OpenCode never has to sniff the
            # terminal for it. A dict here means that decision leaked back.
            if not isinstance(v, str) or not HEX.match(v):
                problems.append(f"{k} = {v!r} is not a plain #rrggbb")
    if problems:
        bad = 1
        for p in problems:
            print(f"  \033[31m✗\033[0m {slug}/opencode: {p}")
    else:
        print(f"  \033[32m✓\033[0m {slug}/opencode: all {len(th)} tokens, all #rrggbb")

sys.exit(bad)
