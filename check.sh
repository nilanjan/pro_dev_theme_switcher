#!/usr/bin/env bash
# One runnable check: drive the app headlessly, assert every target landed.
set -uo pipefail
BIN="${1:-/Applications/NG-Thm-Ch.app/Contents/MacOS/ng-thm-ch}"
fail=0
ok(){ printf '  \033[32m✓\033[0m %-13s %s\n' "$1" "$2"; }
no(){ printf '  \033[31m✗\033[0m %-13s got %-22s want %s\n' "$1" "$2" "$3"; fail=1; }
eq(){ [[ "$2" == "$3" ]] && ok "$1" "$2" || no "$1" "$2" "$3"; }
json(){ python3 -c "import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$1" "$2" 2>/dev/null; }

for m in dark light; do
  echo "== --set $m =="
  "$BIN" --set "$m" >/dev/null 2>&1; sleep 1
  [[ $m == dark ]] && { os=Dark; nv=tokyonight-storm; hd=tokyo-night; cust='15:#24283b'; } \
                   || { os=Light; nv=rose-pine-dawn;  hd=rose-pine-dawn; cust=none; }
  eq macOS     "$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)"    "$os"
  eq alacritty "$(tr -d '[:space:]' < ~/.config/alacritty/theme.mode)"                "$m"
  eq tmux      "$(tr -d '[:space:]' < ~/.tmux/theme.current)"                         "$m"
  eq nvim      "$(tr -d '[:space:]' < ~/.local/share/nvim/theme_state.txt)"           "$nv"
  eq zsh       "$(tr -d '[:space:]' < ~/.zsh_theme_mode)"                             "$m"
  eq claude    "$(json ~/.claude/settings.json theme)"                                "$m"
  eq herdr     "$(sed -n '/^\[theme\]/,/^\[/p' ~/.config/herdr/config.toml | sed -n 's/^name = "\(.*\)"/\1/p')" "$hd"
  # herdr ships no Storm variant: dark overlays 15 custom tokens on tokyo-night, and
  # light must carry NO overlay or it would repaint rose-pine-dawn.
  eq herdr-storm "$(python3 -c "
import tomllib,pathlib
c=tomllib.loads((pathlib.Path.home()/'.config/herdr/config.toml').read_text()).get('theme',{}).get('custom')
print(f\"{len(c)}:{c['surface0']}\" if c else 'none')")" "$cust"
done

echo "== Auto (sunrise/sunset) =="
"$BIN" --set auto >/dev/null 2>&1; sleep 1
eq auto-on  "$(defaults read -g AppleInterfaceStyleSwitchesAutomatically 2>/dev/null || echo 0)" "1"
"$BIN" --set dark >/dev/null 2>&1; sleep 1
eq auto-off "$(defaults read -g AppleInterfaceStyleSwitchesAutomatically 2>/dev/null || echo 0)" "0"

echo "== ANSI black contrast (TUIs draw bullets/box-drawing with ANSI 0) =="
python3 - <<'PY' || fail=1
import re, pathlib, sys
def luma(h):
    r,g,b=(int(h[i:i+2],16)/255 for i in (0,2,4))
    f=lambda c: c/12.92 if c<=0.03928 else ((c+0.055)/1.055)**2.4
    return 0.2126*f(r)+0.7152*f(g)+0.0722*f(b)
def cr(a,b):
    la,lb=luma(a),luma(b); hi,lo=max(la,lb),min(la,lb); return (hi+0.05)/(lo+0.05)
bad=0
for mode,bg in [("dark","24283b"),("light","faf4ed")]:
    ov=(pathlib.Path.home()/f".config/alacritty/themes/custom/{mode}.toml").read_text()
    blk=re.search(r"\[colors\.normal\]\s*\n\s*black\s*=\s*.#(\w{6})", ov).group(1)
    r=cr(bg,blk); good = r >= 2.0; bad |= (not good)
    mark = "\033[32m✓\033[0m" if good else "\033[31m✗\033[0m"
    print(f"  {mark} {mode:<11}   ANSI black #{blk} vs #{bg} = {r:.2f}:1 (need >=2.0)")
sys.exit(bad)
PY
echo; [[ $fail == 0 ]] && echo "ALL PASS" || echo "FAILURES"; exit $fail
