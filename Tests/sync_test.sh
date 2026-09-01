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
has(){ grep -qF "$2" "$3" && ok "$1" || no "$1" "missing from $3"; }

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
run(){ HOME="$SANDBOX" bash "$REPO/config/sync.sh" --quiet "$@"; }

echo "== default themes =="
setup
run light
eq "nvim state"      "$(cat "$SANDBOX/.local/share/nvim/theme_state.txt")" "rose-pine-dawn"
eq "zsh mode"        "$(cat "$SANDBOX/.zsh_theme_mode")"                   "light"
eq "herdr base"      "$(sed -n 's/^name = "\(.*\)"/\1/p' "$SANDBOX/.config/herdr/config.toml")" "rose-pine-dawn"
eq "herdr accent"    "$(sed -n 's/^accent = "\(.*\)"/\1/p' "$SANDBOX/.config/herdr/config.toml")" "#695482"
eq "claude theme"    "$(sed -n 's/.*"theme": "\(.*\)".*/\1/p' "$SANDBOX/.claude/settings.json")" "custom:rose-pine-dawn"
has "alacritty copied" "#f2e9e1" "$SANDBOX/.config/alacritty/themes/custom/light.toml"
has "tmux copied"      "#f2e9e1" "$SANDBOX/.tmux/themes/light.conf"

run dark
eq "nvim state (dark)" "$(cat "$SANDBOX/.local/share/nvim/theme_state.txt")" "tokyonight-storm"
eq "herdr base (dark)" "$(sed -n 's/^name = "\(.*\)"/\1/p' "$SANDBOX/.config/herdr/config.toml")" "tokyo-night"
eq "claude (dark)"     "$(sed -n 's/.*"theme": "\(.*\)".*/\1/p' "$SANDBOX/.claude/settings.json")" "custom:tokyo-night-storm"

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

echo "== every shipped theme is complete =="
for d in "$REPO"/config/themes/*/; do
  slug=$(basename "$d")
  for f in meta alacritty.toml tmux.conf nvim.lua herdr.toml claude.json; do
    [[ -f "$d/$f" ]] && ok "$slug/$f" || no "$slug/$f" "absent"
  done
  for k in mode name nvim herdr accent; do
    v=$(sed -n "s/^$k=//p" "$d/meta")
    [[ -n "$v" ]] && ok "$slug meta.$k=$v" || no "$slug meta.$k" "empty"
  done
done

echo; [[ $fail == 0 ]] && echo "SYNC TESTS PASS" || echo "SYNC TESTS FAILED"; exit $fail
