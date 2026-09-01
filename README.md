# NG-Thm-Ch

Menu bar app that switches macOS **and** your terminal stack between
**Tokyo Night Storm** (dark) and **Rosé Pine Dawn** (light) in one click.

- **left-click** the icon → toggle now
- **right-click** → panel: **Light / Dark / Auto**, per-target opt-out, Launch at Login, Quit

**Auto** hands control to the macOS sunrise/sunset schedule (`SLSSetAppearanceThemeSwitchesAutomatically`
— there is no public API for it). The app keeps syncing because it listens for the
appearance notification, so your terminals follow the schedule too. Picking Light or
Dark explicitly leaves Auto, exactly as System Settings behaves.

## How it works

macOS appearance is the single source of truth. The app flips it, then reacts to
`AppleInterfaceThemeChangedNotification` and runs `~/.config/theme-sync-all.sh`,
which drives Alacritty, tmux, Neovim, herdr and the zsh prompt. Switching from
Control Center or the auto sunrise/sunset schedule therefore works too.

| Target | Dark | Light | Mechanism |
|---|---|---|---|
| macOS | — | — | AppleScript → System Events |
| Alacritty | tokyo-night-storm | rose-pine-dawn | `theme-switch.sh`, live_config_reload |
| tmux | Storm palette | Dawn palette | `theme-switcher.sh`, source-file |
| Neovim | tokyonight-storm | rose-pine-dawn | base46 user themes + FocusGained reload |
| herdr | tokyo-night | rose-pine-dawn | config.toml + `server reload-config` |
| Claude Code | dark | light | `~/.claude/settings.json` `theme` |
| VS Code | Tokyo Night Storm | Rosé Pine Dawn | native `window.autoDetectColorScheme` |

Two upstream ports ship an ANSI black that is invisible on their own background
(Storm `#32344a` = 1.20:1, Dawn `#f2e9e1` = 1.10:1). TUIs draw bullets and
box-drawing with ANSI 0, so those glyphs vanish. `custom/{dark,light}.toml`
override it with canonical palette greys; `check.sh` fails below 2.0:1.

`theme-sync-all.sh` takes a `mkdir` mutex: the app invokes it directly *and* from
its appearance-notification observer, and overlapping runs used to corrupt herdr's
TOML.

## Build / install

```sh
make install      # build, sign, copy to /Applications, launch
make dmg          # dist/NG-Thm-Ch-1.0.dmg
make check        # assert all six targets, both directions
make uninstall
```

Needs Command Line Tools only. Swift 6.4's default XCBuild backend requires full
Xcode, so the Makefile passes `--build-system native`.

## CLI

`ng-thm-ch --set dark|light|auto|toggle` — headless, used by `check.sh` and bound to
`<leader>tt` in Neovim.
