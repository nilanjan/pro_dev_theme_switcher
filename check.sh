#!/usr/bin/env bash
# One runnable check: drive the app headlessly, assert every target landed,
# then gate the palettes so the colour work cannot silently drift back.
set -uo pipefail
cd "$(dirname "$0")"          # the palette gate reads config/ as the source of truth
BIN="${1:-/Applications/ProDev Theme Switcher.app/Contents/MacOS/prodev-theme-switcher}"
fail=0
# The run flips appearance repeatedly and used to end on dark, silently leaving the
# machine somewhere the user did not put it -- and turning Auto off as a side effect
# of the auto-off assertion. Remember where we started and put it back.
START_AUTO=$(defaults read -g AppleInterfaceStyleSwitchesAutomatically 2>/dev/null || echo 0)
START_MODE=$([[ "$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)" == Dark ]] && echo dark || echo light)
ok(){ printf '  \033[32m✓\033[0m %-13s %s\n' "$1" "$2"; }
no(){ printf '  \033[31m✗\033[0m %-13s got %-22s want %s\n' "$1" "$2" "$3"; fail=1; }
eq(){ [[ "$2" == "$3" ]] && ok "$1" "$2" || no "$1" "$2" "$3"; }
json(){ python3 -c "import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$1" "$2" 2>/dev/null; }

for m in dark light; do
  echo "== --set $m =="
  "$BIN" --set "$m" >/dev/null 2>&1; sleep 1
  [[ $m == dark ]] && { os=Dark; slug=tokyo-night-storm; cust='15:#24283b'; } \
                   || { os=Light; slug=rose-pine-dawn;    cust='15:#f2e9e1'; }
  # Per-target identifiers come from the theme's own meta file, so the check reads
  # the same source of truth the sync script does rather than a second copy.
  meta(){ sed -n "s/^$1=//p" "config/themes/$slug/meta" | head -1; }
  nv=$(meta nvim); hd=$(meta herdr); acc=$(meta accent)
  eq macOS     "$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)"    "$os"
  eq alacritty "$(tr -d '[:space:]' < ~/.config/alacritty/theme.mode)"                "$m"
  eq tmux      "$(tr -d '[:space:]' < ~/.tmux/theme.current)"                         "$m"
  eq nvim      "$(tr -d '[:space:]' < ~/.local/share/nvim/theme_state.txt)"           "$nv"
  eq zsh       "$(tr -d '[:space:]' < ~/.zsh_theme_mode)"                             "$m"
  # A real custom theme, not a built-in: see config/sync.sh for why.
  eq claude    "$(json ~/.claude/settings.json theme)"                            "custom:$slug"
  eq claude-thm "$(python3 -c "
import json,pathlib
d=json.load(open(pathlib.Path.home()/'.claude/themes/$slug.json'))
print(f\"{d['base']}:{len(d['overrides'])}\")" 2>/dev/null)"                                 "$m:55"
  eq herdr     "$(sed -n '/^\[theme\]/,/^\[/p' ~/.config/herdr/config.toml | sed -n 's/^name = "\(.*\)"/\1/p')" "$hd"
  # The chip label is surface_dim, shared with the selected sidebar row, so it
  # cannot be darkened alone -- the accent fill is darkened instead until the
  # label clears 4.5:1 on it. Dark pins Storm's blue.
  eq herdr-acc "$(sed -n '/^\[ui\]/,/^\[/p' ~/.config/herdr/config.toml | sed -n 's/^accent = "\(.*\)"/\1/p')" "$acc"
  # Both modes overlay 15 custom tokens: dark because herdr ships no Storm variant,
  # light because herdr's rose-pine-dawn base is 4% off pure white. surface0 is the
  # canvas, so it doubles as the assertion that the right block landed.
  eq herdr-cust "$(python3 -c "
import tomllib,pathlib
c=tomllib.loads((pathlib.Path.home()/'.config/herdr/config.toml').read_text()).get('theme',{}).get('custom')
print(f\"{len(c)}:{c['surface0']}\" if c else 'none')")" "$cust"
done

echo "== Auto (sunrise/sunset) =="
"$BIN" --set auto >/dev/null 2>&1; sleep 1
eq auto-on  "$(defaults read -g AppleInterfaceStyleSwitchesAutomatically 2>/dev/null || echo 0)" "1"
"$BIN" --set dark >/dev/null 2>&1; sleep 1
eq auto-off "$(defaults read -g AppleInterfaceStyleSwitchesAutomatically 2>/dev/null || echo 0)" "0"

echo "== palette gate =="
python3 tests/palette_gate.py || fail=1

[[ "$START_AUTO" == 1 ]] && "$BIN" --set auto >/dev/null 2>&1 \
                         || "$BIN" --set "$START_MODE" >/dev/null 2>&1
echo; echo "restored: $([[ "$START_AUTO" == 1 ]] && echo auto || echo "$START_MODE")"
[[ $fail == 0 ]] && echo "ALL PASS" || echo "FAILURES"; exit $fail
