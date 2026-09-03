#!/usr/bin/env bash
# ProDev Theme Switcher -- apply one theme across every target.
#
# A theme is a directory under themes/<slug>/ holding one file per target plus a
# `meta` file. Adding a theme means adding a directory; nothing here or in the app
# needs to change. `meta` carries the per-target identifiers, because a slug does
# not always match what a target calls the same theme (tokyo-night-storm is
# `tokyonight-storm` to base46 and `tokyo-night` to herdr).
#
#   sync.sh [--quiet] [auto|light|dark]   apply a theme to every installed target
#   sync.sh --install                      copy this directory into ~/.config/prodev-theme-switcher
#   sync.sh --restore                      put every edited file back as it was before the first edit
#
# Each target is wired in, not just written next to: Alacritty gets an import,
# tmux a source-file line, Neovim a require, herdr a [theme] table, Claude Code a
# "theme" key. Each of those is added once, inside a marked block where the file
# allows one, and the file is snapshotted first. That is what makes it work on a
# machine that is not the author's -- the first release only wrote theme files to
# paths the author's own dotfiles happened to read.
set -euo pipefail

ROOT="$HOME/.config/prodev-theme-switcher"
THEMES="$ROOT/themes"
BACKUP="$ROOT/backup/original"
MARK_BEGIN="# >>> ProDev Theme Switcher managed >>>"
MARK_END="# <<< ProDev Theme Switcher managed <<<"

# --install: from wherever this copy lives (the repo's config/, or the .app's
# Resources/config on first launch) into ROOT. Themes are replaced wholesale so a
# removed theme does not linger; state, backups and prefs are left alone.
if [[ "${1:-}" == "--install" ]]; then
  src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  if [[ "$src" != "$(cd "$ROOT" 2>/dev/null && pwd -P)" ]]; then
    mkdir -p "$ROOT"
    rm -rf "$ROOT/themes" "$ROOT/nvim"
    cp -R "$src/themes" "$src/nvim" "$ROOT/"
    install -m 755 "$src/sync.sh" "$ROOT/sync.sh"
  fi
  echo "installed $(ls -1 "$ROOT/themes" | wc -l | tr -d ' ') themes to $ROOT/themes"
  exit 0
fi

if [[ "${1:-}" == "--restore" ]]; then
  [[ -d "$BACKUP" ]] || { echo "nothing backed up under $BACKUP"; exit 0; }
  (cd "$BACKUP" && find . -type f) | while IFS= read -r f; do
    f="${f#./}"
    mkdir -p "$HOME/$(dirname "$f")"
    cp -p "$BACKUP/$f" "$HOME/$f"
    echo "restored ~/$f"
  done
  exit 0
fi

QUIET=0
MODE="${1:-auto}"
if [[ "${1:-}" == "--quiet" ]]; then QUIET=1; MODE="${2:-auto}"; fi

zsh_mode_file="$HOME/.zsh_theme_mode"
nvim_state_file="$HOME/.local/share/nvim/theme_state.txt"
mac_cache_file="$HOME/.cache/macos_theme_mode"

detect_mode() {
  if [[ "$MODE" == "auto" ]]; then
    [[ "$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)" == "Dark" ]] \
      && echo dark || echo light
  else
    echo "$MODE"
  fi
}

# Serialize concurrent runs. The app invokes this directly AND again from its
# AppleInterfaceThemeChangedNotification observer, so two copies can overlap and
# interleave their rewrites of herdr's config (duplicate [theme.custom] -> invalid
# TOML). mkdir is atomic on every filesystem we care about; no flock on macOS.
_lock="$HOME/.cache/prodev-theme-switcher.lock"
mkdir -p "$HOME/.cache"
for _ in $(seq 1 60); do
  if mkdir "$_lock" 2>/dev/null; then
    trap 'rmdir "$_lock" 2>/dev/null || true' EXIT
    break
  fi
  sleep 0.1
done

# The menu bar passes a comma list of targets to leave alone.
skip() { [[ ",${PDTS_SKIP:-}," == *",$1,"* ]]; }

# Which theme is selected for this mode. The app writes these; the env wins so the
# CLI can override without touching state.
selected_theme() {
  local mode="$1" env_val state_file
  if [[ "$mode" == "dark" ]]; then env_val="${PDTS_DARK_THEME:-}"; else env_val="${PDTS_LIGHT_THEME:-}"; fi
  [[ -n "$env_val" ]] && { echo "$env_val"; return; }
  state_file="$ROOT/theme.$mode"
  if [[ -r "$state_file" ]]; then tr -d '[:space:]' < "$state_file"; return; fi
  [[ "$mode" == "dark" ]] && echo tokyo-night-storm || echo rose-pine-dawn
}

meta() { sed -n "s/^$2=//p" "$THEMES/$1/meta" | head -1; }

# Snapshot a user-owned file once, before its first edit. Never overwritten, so it
# stays the pre-install original however many switches follow. --restore puts it
# back. A file that did not exist has no original, and gets none.
backup() {
  local f="$1" dst="$BACKUP/${1#"$HOME"/}"
  [[ -f "$f" && ! -e "$dst" ]] || return 0
  mkdir -p "$(dirname "$dst")"
  cp -p "$f" "$dst"
}

# Append one line inside a marked block, once. Appending puts it after the user's
# own settings, so it wins; the markers say what wrote it and how to take it out.
# The comment leader is the file's own: `#` for TOML and tmux, `--` for Lua,
# `"` for Vimscript -- a `#` in init.lua is a syntax error, not a comment.
ensure_line() {  # file, line, comment-leader
  grep -qF -- "$2" "$1" 2>/dev/null && return 0
  backup "$1"
  mkdir -p "$(dirname "$1")"
  local c="${3:-#}"
  printf '\n%s\n%s\n%s\n' "$c${MARK_BEGIN#\#}" "$2" "$c${MARK_END#\#}" >> "$1"
}

# Alacritty's own search order, so an existing ~/.alacritty.toml is edited rather
# than shadowed by a new file higher up the list.
alacritty_conf() {
  local f
  for f in "$HOME/.config/alacritty/alacritty.toml" "$HOME/.alacritty.toml"; do
    [[ -f "$f" ]] && { echo "$f"; return; }
  done
  echo "$HOME/.config/alacritty/alacritty.toml"
}

tmux_conf() {
  local f
  for f in "$HOME/.tmux.conf" "$HOME/.config/tmux/tmux.conf"; do
    [[ -f "$f" ]] && { echo "$f"; return; }
  done
  [[ -d "$HOME/.config/tmux" ]] && echo "$HOME/.config/tmux/tmux.conf" || echo "$HOME/.tmux.conf"
}

apply_mode() {
  local mode="$1"
  case "$mode" in dark|light) ;; *) echo "usage: $0 [--quiet] [auto|light|dark]" >&2; exit 1 ;; esac

  local slug; slug="$(selected_theme "$mode")"
  if [[ ! -d "$THEMES/$slug" ]]; then
    echo "unknown theme '$slug' for $mode; falling back" >&2
    slug=$([[ "$mode" == dark ]] && echo tokyo-night-storm || echo rose-pine-dawn)
  fi
  local dir="$THEMES/$slug"

  mkdir -p "$HOME/.cache" "$HOME/.local/share/nvim"
  echo "$mode" > "$zsh_mode_file"
  echo "$mode" > "$mac_cache_file"

  # Neovim reads the state file on FocusGained via a module the app installs, so a
  # switch lands in running instances too. The base46 table is for NvChad configs.
  if ! skip nvim; then
    meta "$slug" nvim > "$nvim_state_file"
    local ncfg="$HOME/.config/nvim"
    if [[ -d "$ncfg" ]]; then
      mkdir -p "$ncfg/lua/themes"
      cp "$dir/nvim.lua" "$ncfg/lua/themes/$(meta "$slug" nvim).lua"
      cp "$ROOT/nvim/prodev_theme.lua" "$ncfg/lua/prodev_theme.lua"
      if [[ -f "$ncfg/init.vim" && ! -f "$ncfg/init.lua" ]]; then
        ensure_line "$ncfg/init.vim" 'lua pcall(require, "prodev_theme")' '"'
      else
        ensure_line "$ncfg/init.lua" 'pcall(require, "prodev_theme")' '--'
      fi
    fi
  fi

  # Alacritty loads imports in order and the importing file last, so anything
  # later wins. Ours therefore goes LAST in the import array, and the user's own
  # [colors] tables in the main file -- which would beat any import -- are moved
  # out (the file is backed up first). Alacritty watches imported files, so the
  # switch is live. <mode>.toml is kept for configs that import per-mode files.
  if ! skip alacritty; then
    local acfg; acfg="$(alacritty_conf)"
    local apath='~/.config/alacritty/themes/custom/current.toml'
    mkdir -p "$HOME/.config/alacritty/themes/custom"
    cp "$dir/alacritty.toml" "$HOME/.config/alacritty/themes/custom/$mode.toml"
    cp "$dir/alacritty.toml" "$HOME/.config/alacritty/themes/custom/current.toml"
    if ! grep -qF -- "$apath" "$acfg" 2>/dev/null; then
      backup "$acfg"
      [[ -f "$acfg" ]] || : > "$acfg"
      if grep -q '^\[colors' "$acfg"; then
        awk '/^\[/ { skip = ($0 ~ /^\[colors/) } !skip' "$acfg" > "$acfg.tmp" && mv -f "$acfg.tmp" "$acfg"
      fi
      if grep -qE '^[[:space:]]*import[[:space:]]*=[[:space:]]*\[' "$acfg"; then
        # append as the final element; handles one-line and multi-line arrays,
        # with or without a trailing comma
        awk -v p="$apath" '
          !done && !inarr && /^[[:space:]]*import[[:space:]]*=[[:space:]]*\[/ { inarr = 1 }
          inarr {
            i = index($0, "]")
            if (i) {
              head = substr($0, 1, i - 1); tail = substr($0, i)
              t = acc head; gsub(/[[:space:]]+$/, "", t)
              sep = (t ~ /[\[,]$/) ? "" : ", "
              print head sep "\"" p "\"" tail
              inarr = 0; done = 1; next
            }
            acc = acc $0
          }
          { print }' "$acfg" > "$acfg.tmp" && mv -f "$acfg.tmp" "$acfg"
      elif grep -q '^\[general\]' "$acfg"; then
        /usr/bin/sed -i '' "/^\[general\]/a\\
import = [\"$apath\"]
" "$acfg"
      else
        # ponytail: [general].import is Alacritty >= 0.14 (2024). 0.13 wanted a
        # top-level key, which has to precede every table; not worth the parser.
        printf '\n%s\n[general]\nimport = ["%s"]\n%s\n' "$MARK_BEGIN" "$apath" "$MARK_END" >> "$acfg"
      fi
    fi
    [[ -x "$HOME/.config/alacritty/theme-switch.sh" ]] && \
      "$HOME/.config/alacritty/theme-switch.sh" --quiet "$mode"
  fi

  # tmux: same shape -- fixed file, one source-file line appended to the user's
  # conf so it comes after their own status settings. A running server is told now.
  if ! skip tmux; then
    mkdir -p "$HOME/.tmux/themes"
    cp "$dir/tmux.conf" "$HOME/.tmux/themes/$mode.conf"
    cp "$dir/tmux.conf" "$HOME/.tmux/themes/current.conf"
    ensure_line "$(tmux_conf)" 'source-file ~/.tmux/themes/current.conf'
    [[ -x "$HOME/.tmux/scripts/theme-switcher.sh" ]] && \
      "$HOME/.tmux/scripts/theme-switcher.sh" --quiet "$mode"
    tmux source-file "$HOME/.tmux/themes/current.conf" >/dev/null 2>&1 || true
  fi

  # Claude Code resolves theme:"auto" ONCE at session start by querying the terminal
  # background, so a mid-session flip leaves it stale (light glyphs on a dark bg).
  # Pin it explicitly instead. The built-in themes cannot match a custom palette --
  # the RGB ones hardcode their own near-white message band, and the -ansi ones can
  # only reach the 16 terminal slots, which TUIs already own -- so each theme ships
  # a real custom theme. It goes into ONE fixed file, rewritten on every switch:
  # Claude Code watches ~/.claude/themes for changes but only re-reads the settings
  # key at startup, so a fixed slug is what lets a running session follow the
  # switch live. (The slug is the filename; the display name is the file's `name`.)
  claude_cfg="$HOME/.claude/settings.json"
  claude_ref="custom:prodev-theme-switcher"
  if ! skip claude && [[ -d "$HOME/.claude" ]] && [[ -f "$dir/claude.json" ]]; then
    mkdir -p "$HOME/.claude/themes"
    # atomic: the watcher must never see a half-written file (a .tmp is not .json, so it is ignored)
    cp "$dir/claude.json" "$HOME/.claude/themes/.prodev-theme-switcher.json.tmp"
    mv -f "$HOME/.claude/themes/.prodev-theme-switcher.json.tmp" "$HOME/.claude/themes/prodev-theme-switcher.json"
    backup "$claude_cfg"
    # Decide with the parser, edit with text. plutil -extract addresses the TOP
    # LEVEL by key path; grep does not. Grepping for "theme" also matches a nested
    # one (a statusLine or plugin block), and grepping for the ref value matches it
    # anywhere -- a permission rule, customInstructions. Both used to end the same
    # way: the top-level key never got written, Claude Code could not resolve the
    # slug, and it fell back to its BUILT-IN DARK palette without a word. That is
    # the failure this whole block exists to prevent, so it is verified, not assumed.
    claude_theme() { /usr/bin/plutil -extract theme raw "$claude_cfg" 2>/dev/null || true; }
    if [[ ! -f "$claude_cfg" || -z "$(tr -d '[:space:]{}' < "$claude_cfg")" ]]; then
      # a fresh install has no settings.json, or an empty one -- which plutil
      # would misread as an OpenStep plist and refuse to write back
      printf '{\n  "theme": "%s"\n}\n' "$claude_ref" > "$claude_cfg"
    elif [[ "$(claude_theme)" != "$claude_ref" ]]; then
      if /usr/bin/grep -qE '^[[:space:]]{0,2}(\{[[:space:]]*)?"theme"[[:space:]]*:' "$claude_cfg"; then
        /usr/bin/sed -i '' -E \
          "s|^([[:space:]]{0,2}(\{[[:space:]]*)?\"theme\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"|\1\"$claude_ref\"|" "$claude_cfg"
      else
        # Insert just after the opening brace. plutil would also work here, but it
        # rewrites the whole file and alphabetises every key -- on a settings.json
        # someone has curated that is a hiccup, not a theme switch.
        /usr/bin/sed -i '' "1s|^[[:space:]]*{|{\\
  \"theme\": \"$claude_ref\",|" "$claude_cfg"
      fi
      # Whatever shape the file was in, it now says what we think it says -- or
      # plutil rewrites it. Never silently leave it unset.
      [[ "$(claude_theme)" == "$claude_ref" ]] || \
        /usr/bin/plutil -replace theme -string "$claude_ref" -r "$claude_cfg"
    fi
  fi

  # OpenCode, same shape as Claude Code: one fixed theme file, rewritten on every
  # switch, and the config key pinned once. Two deliberate choices:
  #
  #   * The tokens are written as plain hex, not as {"dark":…,"light":…} variants.
  #     OpenCode supports variants, but it picks between them by sniffing the
  #     terminal background -- the same detection that leaves Claude Code stale
  #     mid-session. The mode is ours to decide, so we decide it.
  #   * The theme lives in tui.json (or tui.jsonc, which OpenCode prefers when both
  #     exist), NOT opencode.json. That moved; writing the old place would be
  #     another file nothing reads.
  oc_dir="$HOME/.config/opencode"
  oc_ref="prodev-theme-switcher"
  if ! skip opencode && [[ -d "$oc_dir" ]] && [[ -f "$dir/opencode.json" ]]; then
    mkdir -p "$oc_dir/themes"
    cp "$dir/opencode.json" "$oc_dir/themes/.$oc_ref.json.tmp"
    mv -f "$oc_dir/themes/.$oc_ref.json.tmp" "$oc_dir/themes/$oc_ref.json"
    oc_cfg="$oc_dir/tui.json"
    [[ -f "$oc_dir/tui.jsonc" ]] && oc_cfg="$oc_dir/tui.jsonc"
    backup "$oc_cfg"
    # tui.json is parsed as JSONC, so plutil is no help here -- a file with comments
    # is valid to OpenCode and unreadable to plutil. Anchor to the top level instead,
    # and check afterwards rather than assuming, for the same reason as Claude Code.
    oc_pinned() { /usr/bin/grep -qE "^[[:space:]]{0,2}(\{[[:space:]]*)?\"theme\"[[:space:]]*:[[:space:]]*\"$oc_ref\"" "$oc_cfg"; }
    if [[ ! -f "$oc_cfg" || -z "$(tr -d '[:space:]{}' < "$oc_cfg")" ]]; then
      printf '{\n  "$schema": "https://opencode.ai/tui.json",\n  "theme": "%s"\n}\n' "$oc_ref" > "$oc_cfg"
    elif ! oc_pinned; then
      if /usr/bin/grep -qE '^[[:space:]]{0,2}(\{[[:space:]]*)?"theme"[[:space:]]*:' "$oc_cfg"; then
        /usr/bin/sed -i '' -E \
          "s|^([[:space:]]{0,2}(\{[[:space:]]*)?\"theme\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"|\1\"$oc_ref\"|" "$oc_cfg"
      else
        /usr/bin/sed -i '' "1s|^[[:space:]]*{|{\\
  \"theme\": \"$oc_ref\",|" "$oc_cfg"
      fi
      oc_pinned || echo "prodev-theme-switcher: could not pin \"theme\" in $oc_cfg; set it to \"$oc_ref\" by hand" >&2
    fi
  fi

  herdr_cfg="$HOME/.config/herdr/config.toml"
  if ! skip herdr && [[ -f "$herdr_cfg" ]]; then
    backup "$herdr_cfg"
    local hname; hname="$(meta "$slug" herdr)"
    # Our block comes off first so the [theme] range below cannot run into it.
    /usr/bin/sed -i '' '/^# >>> ProDev Theme Switcher managed >>>/,/^# <<< ProDev Theme Switcher managed <<</d' "$herdr_cfg"
    /usr/bin/sed -i '' '/^\[theme\.custom\]/,/^$/d' "$herdr_cfg"
    if ! grep -q '^\[theme\]' "$herdr_cfg"; then
      printf '\n[theme]\nname = "%s"\n' "$hname" >> "$herdr_cfg"
    elif ! /usr/bin/sed -n '/^\[theme\]/,/^\[/p' "$herdr_cfg" | grep -q '^name[[:space:]]*='; then
      /usr/bin/sed -i '' "/^\[theme\]/a\\
name = \"$hname\"
" "$herdr_cfg"
    else
      /usr/bin/sed -i '' -E "/^\[theme\]/,/^\[/ s/^name[[:space:]]*=.*/name = \"$hname\"/" "$herdr_cfg"
    fi

    # [ui] accent fills the selected-tab chip and the agent dots. herdr paints the
    # chip label with surface_dim -- the same token as the selected sidebar row --
    # so the label cannot be darkened on its own; each theme darkens the fill until
    # the label clears 4.5:1 on it, and records the result in `meta`.
    local accent; accent="$(meta "$slug" accent)"
    /usr/bin/sed -i '' -E '/^\[ui\]/,/^\[/ { /^accent[[:space:]]*=/d; }' "$herdr_cfg"
    if grep -q '^\[ui\]' "$herdr_cfg"; then
      /usr/bin/sed -i '' -E "/^\[ui\]/a\\
accent = \"$accent\"
" "$herdr_cfg"
    else
      printf '\n[ui]\naccent = "%s"\n' "$accent" >> "$herdr_cfg"
    fi

    # [theme.custom] applies to whatever [theme] name is set, so the block is
    # rewritten wholesale on every switch -- never left behind to repaint the other
    # theme. herdr ships no Tokyo Night *Storm* and its rose-pine-dawn sits 4% off
    # pure white, so both need the overlay.
    {
      echo "$MARK_BEGIN"
      echo "# $slug -- generated, edit themes/$slug/herdr.toml instead"
      cat "$dir/herdr.toml"
      echo "$MARK_END"
    } >> "$herdr_cfg"
    local herdr_bin; herdr_bin="$(command -v herdr 2>/dev/null || echo "$HOME/.local/bin/herdr")"
    [[ -x "$herdr_bin" ]] && "$herdr_bin" server reload-config >/dev/null 2>&1 || true
  fi

  [[ "$QUIET" -ne 1 ]] && echo "prodev-theme-switcher -> $mode ($slug)"
  return 0
}

apply_mode "$(detect_mode)"
