#!/usr/bin/env bash
# Exercises config/sync.sh against a throwaway HOME. The script's real job is
# resolving a slug and rewriting other tools' config files, so the assertions are
# about what it wrote, not about what it printed.
set -uo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
fail=0
ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m✗\033[0m %-42s got %s\n' "$1" "$2"; fail=1; }
eq(){ [[ "$2" == "$3" ]] && ok "$1" || no "$1" "'$2' want '$3'"; }
has(){ grep -qF -- "$2" "$3" && ok "$1" || no "$1" "missing from $3"; }

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

setup(){
  rm -rf "$SANDBOX"; mkdir -p "$SANDBOX"
  mkdir -p "$SANDBOX/.config/prodev-theme-switcher" "$SANDBOX/.config/herdr" \
           "$SANDBOX/.claude" "$SANDBOX/.local/share/nvim" "$SANDBOX/.cache"
  cp -R "$REPO/config/themes" "$SANDBOX/.config/prodev-theme-switcher/themes"
  printf '[theme]\nname = "placeholder"\n\n[ui]\nconfirm_close = true\n' \
    > "$SANDBOX/.config/herdr/config.toml"
  printf '{\n  "theme": "auto"\n}\n' > "$SANDBOX/.claude/settings.json"
}
run(){ TMUX_TMPDIR="$SANDBOX" HOME="$SANDBOX" bash "$REPO/config/sync.sh" --quiet "$@"; }

echo "== default themes =="
setup
run light
eq "nvim state"      "$(cat "$SANDBOX/.local/share/nvim/theme_state.txt")" "rose-pine-dawn"
eq "zsh mode"        "$(cat "$SANDBOX/.zsh_theme_mode")"                   "light"
eq "herdr base"      "$(sed -n 's/^name = "\(.*\)"/\1/p' "$SANDBOX/.config/herdr/config.toml")" "rose-pine-dawn"
eq "herdr accent"    "$(sed -n 's/^accent = "\(.*\)"/\1/p' "$SANDBOX/.config/herdr/config.toml")" "#695482"
eq "claude theme"    "$(sed -n 's/.*"theme": "\(.*\)".*/\1/p' "$SANDBOX/.claude/settings.json")" "custom:prodev-theme-switcher"
eq "claude file"     "$(plutil -extract name raw "$SANDBOX/.claude/themes/prodev-theme-switcher.json" 2>&1)" "Rosé Pine Dawn"
has "alacritty copied" "#f2e9e1" "$SANDBOX/.config/alacritty/themes/custom/light.toml"
has "tmux copied"      "#f2e9e1" "$SANDBOX/.tmux/themes/light.conf"

run dark
eq "nvim state (dark)" "$(cat "$SANDBOX/.local/share/nvim/theme_state.txt")" "tokyonight-storm"
eq "herdr base (dark)" "$(sed -n 's/^name = "\(.*\)"/\1/p' "$SANDBOX/.config/herdr/config.toml")" "tokyo-night"
eq "claude (dark)"     "$(sed -n 's/.*"theme": "\(.*\)".*/\1/p' "$SANDBOX/.claude/settings.json")" "custom:prodev-theme-switcher"
# The slug never changes; the file behind it does. That is what a running Claude
# Code session can follow -- it watches the file, and reads the key only at start.
eq "claude file (dark)" "$(plutil -extract name raw "$SANDBOX/.claude/themes/prodev-theme-switcher.json" 2>&1)" "Tokyo Night Storm"
eq "claude file base"   "$(plutil -extract base raw "$SANDBOX/.claude/themes/prodev-theme-switcher.json" 2>&1)" "dark"

echo "== the managed block does not accumulate =="
# Overlapping runs used to leave two [theme.custom] tables behind, which is invalid
# TOML and silently broke herdr's whole config.
run light; run dark; run light
eq "one theme.custom"  "$(grep -c '^\[theme.custom\]' "$SANDBOX/.config/herdr/config.toml")" "1"
eq "one accent"        "$(grep -c '^accent = '        "$SANDBOX/.config/herdr/config.toml")" "1"
eq "one managed block" "$(grep -c '^# >>> ProDev Theme Switcher managed >>>' "$SANDBOX/.config/herdr/config.toml")" "1"
eq "still valid toml"  "$(HOME=$SANDBOX python3 -c "
import tomllib,pathlib,os
tomllib.loads((pathlib.Path(os.environ['HOME'])/'.config/herdr/config.toml').read_text())
print('ok')" 2>&1)" "ok"

echo "== env overrides the default =="
setup
PDTS_LIGHT_THEME=tokyo-night-storm run light
eq "env-selected slug" "$(cat "$SANDBOX/.local/share/nvim/theme_state.txt")" "tokyonight-storm"

echo "== unknown theme falls back rather than half-applying =="
setup
PDTS_LIGHT_THEME=no-such-theme run light 2>/dev/null
eq "fell back to shipped" "$(cat "$SANDBOX/.local/share/nvim/theme_state.txt")" "rose-pine-dawn"

echo "== per-target opt-out =="
setup
PDTS_SKIP=herdr,claude run light
eq "herdr untouched"  "$(sed -n 's/^name = "\(.*\)"/\1/p' "$SANDBOX/.config/herdr/config.toml")" "placeholder"
eq "claude untouched" "$(sed -n 's/.*"theme": "\(.*\)".*/\1/p' "$SANDBOX/.claude/settings.json")" "auto"
eq "nvim still themed" "$(cat "$SANDBOX/.local/share/nvim/theme_state.txt")" "rose-pine-dawn"

echo "== a fresh machine: the tools are there, none of the author's dotfile hooks are =="
# This is the bug that shipped. sync.sh copied theme files to paths that only the
# author's own dotfiles read (theme-switch.sh, theme-switcher.sh, theme_manager.lua)
# and edited [theme]/"theme" keys that only the author's configs already had. On any
# other Mac the files appeared and nothing changed. So: bare configs, no hooks.
fresh(){
  rm -rf "$SANDBOX"
  mkdir -p "$SANDBOX/.config/prodev-theme-switcher" "$SANDBOX/.config/alacritty" \
           "$SANDBOX/.config/nvim" "$SANDBOX/.config/herdr" "$SANDBOX/.claude"
  cp -R "$REPO/config/themes" "$SANDBOX/.config/prodev-theme-switcher/themes"
  cp -R "$REPO/config/nvim"   "$SANDBOX/.config/prodev-theme-switcher/nvim"
  printf '[font]\nsize = 13\n'          > "$SANDBOX/.config/alacritty/alacritty.toml"
  printf 'set -g mouse on\n'            > "$SANDBOX/.tmux.conf"
  printf 'vim.o.number = true\n'        > "$SANDBOX/.config/nvim/init.lua"
  printf '[ui]\nconfirm_close = true\n' > "$SANDBOX/.config/herdr/config.toml"   # no [theme]
  printf '{\n  "permissions": {}\n}\n'  > "$SANDBOX/.claude/settings.json"        # no "theme"
}
toml_ok(){ python3 -c "import tomllib,sys; tomllib.loads(open(sys.argv[1]).read()); print('ok')" "$1" 2>&1 | tail -1; }
fresh
run light
A="$SANDBOX/.config/alacritty"
has "alacritty.toml imports the managed file"  'themes/custom/current.toml' "$A/alacritty.toml"
eq  "alacritty.toml is still valid TOML"        "$(toml_ok "$A/alacritty.toml")" "ok"
has "alacritty current.toml is the light theme" '#f2e9e1' "$A/themes/custom/current.toml"
has "tmux.conf sources the managed file"        'source-file ~/.tmux/themes/current.conf' "$SANDBOX/.tmux.conf"
has "tmux current.conf is the light theme"      '#f2e9e1' "$SANDBOX/.tmux/themes/current.conf"
has "init.lua loads the switcher module"        'pcall(require, "prodev_theme")' "$SANDBOX/.config/nvim/init.lua"
[[ -f "$SANDBOX/.config/nvim/lua/prodev_theme.lua" ]] && ok "prodev_theme.lua installed" || no "prodev_theme.lua installed" "absent"
[[ -f "$SANDBOX/.config/nvim/lua/themes/rose-pine-dawn.lua" ]] && ok "base46 table installed" || no "base46 table installed" "absent"
eq  "herdr got a [theme] table"                 "$(sed -n 's/^name = "\(.*\)"/\1/p' "$SANDBOX/.config/herdr/config.toml")" "rose-pine-dawn"
eq  "herdr config is still valid TOML"          "$(toml_ok "$SANDBOX/.config/herdr/config.toml")" "ok"
eq  "claude got a theme key"                    "$(plutil -extract theme raw "$SANDBOX/.claude/settings.json" 2>&1)" "custom:prodev-theme-switcher"
[[ -f "$SANDBOX/.claude/themes/prodev-theme-switcher.json" ]] && ok "claude theme file installed" || no "claude theme file installed" "absent"
# The markers must be comments in the host language: `#` is not one in Lua.
has "init.lua block uses Lua comments" '-- >>> ProDev Theme Switcher managed >>>' "$SANDBOX/.config/nvim/init.lua"
if command -v nvim >/dev/null; then
  # A real Neovim loads the edited init.lua and our module; with no colorscheme
  # plugin installed the module falls back to flipping `background`.
  eq "a real nvim loaded it and flipped background" "$(cd "$SANDBOX" && HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX/.config" XDG_DATA_HOME="$SANDBOX/.local/share" XDG_STATE_HOME="$SANDBOX/.local/state" \
      nvim --headless -u "$SANDBOX/.config/nvim/init.lua" -c 'lua io.write(vim.o.background)' -c 'qa!' 2>&1 | tail -1)" "light"
else
  ok "a real nvim loaded it (skipped: no nvim here)"
fi
fresh; rm "$SANDBOX/.config/nvim/init.lua"; printf 'set number\n' > "$SANDBOX/.config/nvim/init.vim"
run light
has "init.vim gets the vimscript form" '" >>> ProDev Theme Switcher managed >>>' "$SANDBOX/.config/nvim/init.vim"
has "init.vim loads via :lua"          'lua pcall(require, "prodev_theme")'      "$SANDBOX/.config/nvim/init.vim"
fresh; run light
# The one assertion that would have caught this: a real tmux reading the real file.
if command -v tmux >/dev/null; then
  sock="$SANDBOX/tmux.sock"
  HOME="$SANDBOX" tmux -S "$sock" -f "$SANDBOX/.tmux.conf" new-session -d 2>/dev/null
  eq "a real tmux applied the theme" "$(tmux -S "$sock" show -gv status-style 2>&1)" "fg=#575279,bg=#dfdad9"
  tmux -S "$sock" kill-server 2>/dev/null
else
  ok "a real tmux applied the theme (skipped: no tmux here)"
fi

run dark
has "alacritty current.toml flipped to dark"    '#24283b' "$A/themes/custom/current.toml"
has "tmux current.conf flipped to dark"         '#24283b' "$SANDBOX/.tmux/themes/current.conf"
eq  "import line written once"                  "$(grep -c 'current.toml'   "$A/alacritty.toml")"          "1"
eq  "source-file line written once"             "$(grep -c 'current.conf'   "$SANDBOX/.tmux.conf")"        "1"
eq  "require line written once"                 "$(grep -c 'prodev_theme'   "$SANDBOX/.config/nvim/init.lua")" "1"
eq  "one [theme] table"                         "$(grep -c '^\[theme\]'     "$SANDBOX/.config/herdr/config.toml")" "1"

echo "== an existing import array is joined -- ours LAST, because later imports win =="
last_import(){ python3 -c "
import tomllib; d=tomllib.loads(open('$1').read()); i=d['general']['import']; print(len(i), i[-1].rsplit('/',1)[-1])"; }
fresh
printf '[general]\nimport = [\n  "~/.config/alacritty/mine.toml",\n]\n\n[font]\nsize = 13\n' > "$A/alacritty.toml"
run light
eq "multi-line, trailing comma: valid"  "$(toml_ok "$A/alacritty.toml")" "ok"
eq "multi-line, trailing comma: last"   "$(last_import "$A/alacritty.toml" 2>&1)" "2 current.toml"
fresh
printf '[general]\nimport = [\n  "~/.config/alacritty/mine.toml"\n]\n' > "$A/alacritty.toml"
run light
eq "multi-line, no comma: valid"        "$(toml_ok "$A/alacritty.toml")" "ok"
eq "multi-line, no comma: last"         "$(last_import "$A/alacritty.toml" 2>&1)" "2 current.toml"
fresh
printf '[general]\nimport = ["~/.config/alacritty/a.toml", "~/.config/alacritty/b.toml"]\n' > "$A/alacritty.toml"
run light
eq "one-line: valid"                    "$(toml_ok "$A/alacritty.toml")" "ok"
eq "one-line: last"                     "$(last_import "$A/alacritty.toml" 2>&1)" "3 current.toml"
fresh
printf '[general]\nimport = []\n' > "$A/alacritty.toml"
run light
eq "empty array: last"                  "$(last_import "$A/alacritty.toml" 2>&1)" "1 current.toml"

echo "== the user's own [colors] would beat any import, so they are moved out (backed up) =="
fresh
printf '[font]\nsize = 13\n\n[colors.primary]\nbackground = "#000000"\n\n[colors.normal]\nblack = "#111111"\n\n[window]\nopacity = 0.9\n' > "$A/alacritty.toml"
run light
eq "still valid TOML"        "$(toml_ok "$A/alacritty.toml")" "ok"
eq "inline colors gone"      "$(grep -c '^\[colors' "$A/alacritty.toml")" "0"
has "other tables kept"      'opacity = 0.9' "$A/alacritty.toml"
has "…and backed up first"   'background = "#000000"' "$SANDBOX/.config/prodev-theme-switcher/backup/original/.config/alacritty/alacritty.toml"

echo "== a ~/.alacritty.toml is edited, not shadowed by a new file =="
fresh; rm "$A/alacritty.toml"; printf '[font]\nsize = 13\n' > "$SANDBOX/.alacritty.toml"
run light
has "import went to ~/.alacritty.toml" 'current.toml' "$SANDBOX/.alacritty.toml"
[[ -e "$A/alacritty.toml" ]] && no "no shadowing alacritty.toml created" "created" || ok "no shadowing alacritty.toml created"

echo "== Claude Code installed but never configured: settings.json is created, not skipped =="
fresh; rm "$SANDBOX/.claude/settings.json"
run light
eq "theme key in a new settings.json" "$(plutil -extract theme raw "$SANDBOX/.claude/settings.json" 2>&1)" "custom:prodev-theme-switcher"

echo "== the Claude theme key lands whatever shape settings.json is in =="
# Every one of these used to end with no TOP-LEVEL "theme" key, which Claude Code
# resolves to its built-in dark palette in silence -- light terminal, dark colours.
claude_theme(){ /usr/bin/plutil -extract theme raw "$SANDBOX/.claude/settings.json" 2>&1 | head -1; }
fresh; printf '{\n  "permissions": {},\n  "statusLine": { "type": "command", "theme": "powerline-dark" }\n}\n' > "$SANDBOX/.claude/settings.json"
run light
eq "nested \"theme\" does not absorb the write" "$(claude_theme)" "custom:prodev-theme-switcher"
eq "…and the nested key is left alone"          "$(python3 -c "import json;print(json.load(open('$SANDBOX/.claude/settings.json'))['statusLine']['theme'])" 2>&1)" "powerline-dark"

fresh; printf '{\n  "theme": "dark",\n  "autoMode": { "soft_deny": ["do not touch custom:prodev-theme-switcher"] }\n}\n' > "$SANDBOX/.claude/settings.json"
run light
eq "the ref appearing elsewhere is not 'already pinned'" "$(claude_theme)" "custom:prodev-theme-switcher"

fresh; printf '{\n  "env": { "FOO": "bar" },\n  "model": "opus"\n}\n' > "$SANDBOX/.claude/settings.json"
run light
eq "no theme key: one is inserted"   "$(claude_theme)" "custom:prodev-theme-switcher"
# plutil would alphabetise every key; someone's curated settings.json is not ours to reorder.
eq "…without reordering their keys" "$(python3 -c "import json;print(','.join(json.load(open('$SANDBOX/.claude/settings.json'))))" 2>&1)" "theme,env,model"

echo "== OpenCode: themed when installed, untouched when not =="
# Same shape as Claude Code -- one fixed theme file rewritten per switch, the key
# pinned once -- so the same failure applies: a "theme" that names a file OpenCode
# cannot find leaves it on its default. tui.json is JSONC, so this is checked by
# reading the file, not by plutil (which cannot parse a comment).
oc_theme(){ sed -n 's|.*"theme"[[:space:]]*:[[:space:]]*"\([^"]*\)".*|\1|p' "$SANDBOX/.config/opencode/$1" | head -1; }
oc_bg(){ python3 -c "import json;print(json.load(open('$SANDBOX/.config/opencode/themes/prodev-theme-switcher.json'))['theme']['background'])" 2>&1; }

fresh; mkdir -p "$SANDBOX/.config/opencode"          # installed, never configured
run light
eq "tui.json created and pinned"  "$(oc_theme tui.json)" "prodev-theme-switcher"
eq "theme file is the light one"  "$(oc_bg)"             "#f2e9e1"
run dark
eq "same file, dark colours"      "$(oc_bg)"             "#24283b"
eq "…and the key is not rewritten" "$(grep -c '"theme"' "$SANDBOX/.config/opencode/tui.json")" "1"

fresh; mkdir -p "$SANDBOX/.config/opencode"
printf '{\n  // mine\n  "theme": "gruvbox",\n  "scroll_speed": 3\n}\n' > "$SANDBOX/.config/opencode/tui.json"
run light
eq "an existing theme is replaced"      "$(oc_theme tui.json)" "prodev-theme-switcher"
has "…and the JSONC comment survives"   '// mine' "$SANDBOX/.config/opencode/tui.json"

fresh; mkdir -p "$SANDBOX/.config/opencode"
printf '{ "theme": "nord" }\n' > "$SANDBOX/.config/opencode/tui.json"
run light
# A one-line object put "theme" past a start-of-line anchor, so the key was
# INSERTED alongside the old one -- two "theme" keys, and JSON takes the last.
eq "a one-line tui.json is edited, not duplicated" "$(grep -c '"theme"' "$SANDBOX/.config/opencode/tui.json")" "1"
eq "…and it is ours"                               "$(oc_theme tui.json)" "prodev-theme-switcher"

fresh; mkdir -p "$SANDBOX/.config/opencode"
printf '{\n  "cursor": { "theme": "block" }\n}\n' > "$SANDBOX/.config/opencode/tui.json"
run light
eq "a nested theme does not absorb the write" "$(oc_theme tui.json)" "prodev-theme-switcher"
has "…and the nested one is left alone"       '"theme": "block"' "$SANDBOX/.config/opencode/tui.json"

fresh; mkdir -p "$SANDBOX/.config/opencode"
printf '{ "theme": "nord" }\n' > "$SANDBOX/.config/opencode/tui.json"
printf '{ "theme": "nord" }\n' > "$SANDBOX/.config/opencode/tui.jsonc"
run light
eq "tui.jsonc wins when both exist" "$(oc_theme tui.jsonc)" "prodev-theme-switcher"
eq "…and tui.json is left alone"    "$(oc_theme tui.json)"  "nord"

fresh   # no ~/.config/opencode at all
run light
[[ -e "$SANDBOX/.config/opencode" ]] && no "not installed: nothing invented" "created" || ok "not installed: nothing invented"

fresh; mkdir -p "$SANDBOX/.config/opencode"
PDTS_SKIP=opencode run light
[[ -e "$SANDBOX/.config/opencode/themes" ]] && no "PDTS_SKIP=opencode honoured" "themed anyway" || ok "PDTS_SKIP=opencode honoured"

echo "== originals are backed up once, before the first edit, and --restore puts them back =="
fresh
run light; run dark
B="$SANDBOX/.config/prodev-theme-switcher/backup/original"
eq "alacritty.toml original" "$(cat "$B/.config/alacritty/alacritty.toml" 2>&1)" "$(printf '[font]\nsize = 13')"
eq "tmux.conf original"      "$(cat "$B/.tmux.conf" 2>&1)"                      "set -g mouse on"
eq "init.lua original"       "$(cat "$B/.config/nvim/init.lua" 2>&1)"           "vim.o.number = true"
eq "herdr original"          "$(cat "$B/.config/herdr/config.toml" 2>&1)"       "$(printf '[ui]\nconfirm_close = true')"
eq "claude original"         "$(cat "$B/.claude/settings.json" 2>&1)"           "$(printf '{\n  "permissions": {}\n}')"
HOME="$SANDBOX" bash "$REPO/config/sync.sh" --restore >/dev/null 2>&1
eq "restored alacritty.toml" "$(cat "$A/alacritty.toml")"                   "$(printf '[font]\nsize = 13')"
eq "restored tmux.conf"      "$(cat "$SANDBOX/.tmux.conf")"                 "set -g mouse on"
eq "restored init.lua"       "$(cat "$SANDBOX/.config/nvim/init.lua")"      "vim.o.number = true"
eq "restored herdr"          "$(cat "$SANDBOX/.config/herdr/config.toml")"  "$(printf '[ui]\nconfirm_close = true')"
eq "restored claude"         "$(cat "$SANDBOX/.claude/settings.json")"      "$(printf '{\n  "permissions": {}\n}')"
# A file the app created from nothing has no original -- and must not be "restored" over.
fresh; rm "$SANDBOX/.tmux.conf"
run light
[[ -e "$B/.tmux.conf" ]] && no "no phantom original for a created file" "backup exists" || ok "no phantom original for a created file"

echo "== --install lays down what the app needs, from the repo or the bundle =="
rm -rf "$SANDBOX"; mkdir -p "$SANDBOX"
HOME="$SANDBOX" bash "$REPO/config/sync.sh" --install >/dev/null
R="$SANDBOX/.config/prodev-theme-switcher"
[[ -x "$R/sync.sh" ]]                         && ok "sync.sh installed"        || no "sync.sh installed" "absent"
[[ -f "$R/themes/rose-pine-dawn/meta" ]]      && ok "themes installed"         || no "themes installed" "absent"
[[ -f "$R/nvim/prodev_theme.lua" ]]           && ok "nvim module staged"       || no "nvim module staged" "absent"
[[ -e "$SANDBOX/.claude" ]]                   && no "nothing invented for absent tools" ".claude created" || ok "nothing invented for absent tools"
HOME="$SANDBOX" bash "$R/sync.sh" --install >/dev/null 2>&1
eq "installed copy can re-run --install harmlessly" "$?" "0"

echo "== every shipped theme is complete =="
for d in "$REPO"/config/themes/*/; do
  slug=$(basename "$d")
  for f in meta alacritty.toml tmux.conf nvim.lua herdr.toml claude.json opencode.json; do
    [[ -f "$d/$f" ]] && ok "$slug/$f" || no "$slug/$f" "absent"
  done
  # A theme that `import`s a file outside the repo is broken on any machine that
  # does not happen to have that file. This shipped once; it is asserted now.
  if grep -qE '^[[:space:]]*import[[:space:]]*=' "$d/alacritty.toml"; then
    no "$slug alacritty.toml self-contained" "imports an external file"
  else
    ok "$slug alacritty.toml self-contained"
  fi
  # Parse it, rather than grepping: `background` also appears under
  # [colors.selection], so a line count says nothing about the canvas.
  eq "$slug canvas is a hex colour" "$(python3 -c "
import tomllib,pathlib,re
d=tomllib.loads(pathlib.Path('$d/alacritty.toml').read_text())
bg=d['colors']['primary']['background']
print('ok' if re.fullmatch(r'#[0-9a-fA-F]{6}', bg) else f'bad:{bg}')" 2>&1 | tail -1)" "ok"
  for k in mode name nvim herdr accent; do
    v=$(sed -n "s/^$k=//p" "$d/meta")
    [[ -n "$v" ]] && ok "$slug meta.$k=$v" || no "$slug meta.$k" "empty"
  done
done

echo "== CI workflow parses =="
# This is here because it already broke once: an embedded python block sat at
# column 0 inside a `run: |` scalar, which silently ends the block. GitHub reported
# it only as "workflow file issue" after the push, with no log.
#
# The point of the check is to catch that BEFORE a push -- GitHub validates the
# file server-side anyway. So where pyyaml is absent (the CI runner, as it turns
# out) it reports a skip rather than failing: a red build there would be this
# check breaking the thing it exists to protect.
yamlcheck=$(python3 - <<'PY' 2>&1
try:
    import yaml
except ImportError:
    print("SKIP"); raise SystemExit
try:
    d = yaml.safe_load(open(".github/workflows/ci.yml"))
    job = d["jobs"]["test"]
    assert job["runs-on"].startswith("macos"), job["runs-on"]
    print(f"ok:{len(job['steps'])} steps")
except Exception as e:
    print(f"INVALID: {e}")
PY
)
case "$yamlcheck" in
  SKIP)  printf '  \033[33m~\033[0m %s\n' "ci.yml unchecked (no pyyaml here)" ;;
  ok:*)  ok "ci.yml is valid YAML, $yamlcheck" ;;
  *)     no "ci.yml is valid YAML" "$yamlcheck" ;;
esac

echo; [[ $fail == 0 ]] && echo "SYNC TESTS PASS" || echo "SYNC TESTS FAILED"; exit $fail
