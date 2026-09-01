#!/usr/bin/env bash
set -euo pipefail

QUIET=0
MODE="${1:-auto}"

if [[ "${1:-}" == "--quiet" ]]; then
  QUIET=1
  MODE="${2:-auto}"
fi

zsh_mode_file="$HOME/.zsh_theme_mode"
nvim_state_file="$HOME/.local/share/nvim/theme_state.txt"
mac_cache_file="$HOME/.cache/macos_theme_mode"

detect_mode() {
  if [[ "$MODE" == "auto" ]]; then
    if [[ "$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)" == "Dark" ]]; then
      echo "dark"
    else
      echo "light"
    fi
  else
    echo "$MODE"
  fi
}

# Serialize concurrent runs. NG-Thm-Ch invokes this directly AND again from its
# AppleInterfaceThemeChangedNotification observer, so two copies can overlap and
# interleave their rewrites of herdr's config (duplicate [theme.custom] -> invalid
# TOML). mkdir is atomic on every filesystem we care about; no flock on macOS.
_lock="$HOME/.cache/theme-sync-all.lock"
mkdir -p "$HOME/.cache"
for _ in $(seq 1 60); do
  if mkdir "$_lock" 2>/dev/null; then
    trap 'rmdir "$_lock" 2>/dev/null || true' EXIT
    break
  fi
  sleep 0.1
done

# NG-Thm-Ch menu bar passes a comma list of targets to leave alone.
skip() { [[ ",${NGTHMCH_SKIP:-}," == *",$1,"* ]]; }

apply_mode() {
  local mode="$1"
  case "$mode" in
    dark|light) ;;
    *)
      echo "usage: $0 [--quiet] [auto|light|dark]" >&2
      exit 1
      ;;
  esac

  mkdir -p "$HOME/.cache" "$HOME/.local/share/nvim"
  echo "$mode" > "$zsh_mode_file"
  echo "$mode" > "$mac_cache_file"

  if ! skip nvim; then
    if [[ "$mode" == "dark" ]]; then
      echo "tokyonight-storm" > "$nvim_state_file"
    else
      echo "rose-pine-dawn" > "$nvim_state_file"
    fi
  fi

  if ! skip alacritty && [[ -x "$HOME/.config/alacritty/theme-switch.sh" ]]; then
    "$HOME/.config/alacritty/theme-switch.sh" --quiet "$mode"
  fi
  if ! skip tmux && [[ -x "$HOME/.tmux/scripts/theme-switcher.sh" ]]; then
    "$HOME/.tmux/scripts/theme-switcher.sh" --quiet "$mode"
  fi

  # herdr: rewrite [theme] name, then reload the running server (if any)
  herdr_cfg="$HOME/.config/herdr/config.toml"
  herdr_bin="$HOME/.local/bin/herdr"
  # Claude Code resolves theme:"auto" ONCE at session start by querying the terminal
  # background, so a mid-session flip leaves it stale (light glyphs on a dark bg).
  # Pin it explicitly instead. Minimal sed so the file keeps its formatting.
  claude_cfg="$HOME/.claude/settings.json"
  if ! skip claude && [[ -f "$claude_cfg" ]]; then
    /usr/bin/sed -i '' -E "s/(\"theme\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"/\1\"$mode\"/" "$claude_cfg"
  fi

  if ! skip herdr && [[ -f "$herdr_cfg" ]]; then
    if [[ "$mode" == "dark" ]]; then herdr_theme="tokyo-night"; else herdr_theme="rose-pine-dawn"; fi
    /usr/bin/sed -i '' -E "/^\\[theme\\]/,/^\\[/ s/^name = \".*\"/name = \"$herdr_theme\"/" "$herdr_cfg"

    # herdr ships no Tokyo Night *Storm*, only Night. Overlay the Storm palette on
    # top of tokyo-night in dark mode only -- [theme.custom] applies to whatever
    # [theme] name is set, so leaving it in place would repaint rose-pine-dawn too.
    /usr/bin/sed -i '' '/^# >>> NG-Thm-Ch managed >>>/,/^# <<< NG-Thm-Ch managed <<</d' "$herdr_cfg"
    /usr/bin/sed -i '' '/^\[theme\.custom\]/,/^$/d' "$herdr_cfg"
    if [[ "$mode" == "dark" ]]; then
      cat >> "$herdr_cfg" <<'HERDR_STORM'
# >>> NG-Thm-Ch managed >>>
# Tokyo Night Storm palette overlaid on herdr's tokyo-night (Night) base.
[theme.custom]
panel_bg    = "#1f2335"
surface0    = "#24283b"
surface1    = "#3b4261"
surface_dim = "#1f2335"
overlay0    = "#565f89"
overlay1    = "#737aa2"
text        = "#c0caf5"
subtext0    = "#a9b1d6"
mauve       = "#bb9af7"
green       = "#9ece6a"
yellow      = "#e0af68"
red         = "#f7768e"
blue        = "#7aa2f7"
teal        = "#73daca"
peach       = "#ff9e64"
# <<< NG-Thm-Ch managed <<<
HERDR_STORM
    fi
    [[ -x "$herdr_bin" ]] && "$herdr_bin" server reload-config >/dev/null 2>&1 || true
  fi

  if [[ "$QUIET" -ne 1 ]]; then
    echo "theme-sync-all -> $mode"
  fi
}

apply_mode "$(detect_mode)"
