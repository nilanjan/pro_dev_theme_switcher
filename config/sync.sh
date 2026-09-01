#!/usr/bin/env bash
# ProDev Theme Switcher -- apply one theme across every target.
#
# A theme is a directory under themes/<slug>/ holding one file per target plus a
# `meta` file. Adding a theme means adding a directory; nothing here or in the app
# needs to change. `meta` carries the per-target identifiers, because a slug does
# not always match what a target calls the same theme (tokyo-night-storm is
# `tokyonight-storm` to base46 and `tokyo-night` to herdr).
set -euo pipefail

ROOT="$HOME/.config/prodev-theme-switcher"
THEMES="$ROOT/themes"

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

  if ! skip nvim; then
    meta "$slug" nvim > "$nvim_state_file"
  fi

  # Alacritty and tmux keep switching on mode, so the selected theme's file is
  # copied into the mode slot rather than teaching their switchers about slugs.
  if ! skip alacritty; then
    mkdir -p "$HOME/.config/alacritty/themes/custom"
    cp "$dir/alacritty.toml" "$HOME/.config/alacritty/themes/custom/$mode.toml"
    [[ -x "$HOME/.config/alacritty/theme-switch.sh" ]] && \
      "$HOME/.config/alacritty/theme-switch.sh" --quiet "$mode"
  fi
  if ! skip tmux; then
    mkdir -p "$HOME/.tmux/themes"
    cp "$dir/tmux.conf" "$HOME/.tmux/themes/$mode.conf"
    [[ -x "$HOME/.tmux/scripts/theme-switcher.sh" ]] && \
      "$HOME/.tmux/scripts/theme-switcher.sh" --quiet "$mode"
  fi

  # Claude Code resolves theme:"auto" ONCE at session start by querying the terminal
  # background, so a mid-session flip leaves it stale (light glyphs on a dark bg).
  # Pin it explicitly instead. The built-in themes cannot match a custom palette --
  # the RGB ones hardcode their own near-white message band, and the -ansi ones can
  # only reach the 16 terminal slots, which TUIs already own -- so each theme ships
  # a real custom theme in ~/.claude/themes, referenced as custom:<slug>.
  claude_cfg="$HOME/.claude/settings.json"
  if ! skip claude && [[ -f "$claude_cfg" ]] && [[ -f "$dir/claude.json" ]]; then
    /usr/bin/sed -i '' -E \
      "s/(\"theme\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"/\1\"custom:$slug\"/" "$claude_cfg"
  fi

  herdr_cfg="$HOME/.config/herdr/config.toml"
  herdr_bin="$HOME/.local/bin/herdr"
  if ! skip herdr && [[ -f "$herdr_cfg" ]]; then
    /usr/bin/sed -i '' -E \
      "/^\[theme\]/,/^\[/ s/^name = \".*\"/name = \"$(meta "$slug" herdr)\"/" "$herdr_cfg"

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
    /usr/bin/sed -i '' '/^# >>> ProDev Theme Switcher managed >>>/,/^# <<< ProDev Theme Switcher managed <<</d' "$herdr_cfg"
    /usr/bin/sed -i '' '/^\[theme\.custom\]/,/^$/d' "$herdr_cfg"
    {
      echo "# >>> ProDev Theme Switcher managed >>>"
      echo "# $slug -- generated, edit themes/$slug/herdr.toml instead"
      cat "$dir/herdr.toml"
      echo "# <<< ProDev Theme Switcher managed <<<"
    } >> "$herdr_cfg"
    [[ -x "$herdr_bin" ]] && "$herdr_bin" server reload-config >/dev/null 2>&1 || true
  fi

  [[ "$QUIET" -ne 1 ]] && echo "prodev-theme-switcher -> $mode ($slug)"
  return 0
}

apply_mode "$(detect_mode)"
