# Legal & Usage Disclaimers

**Read this before installing.** By downloading, building, installing or running
ProDev Theme Switcher ("the Software") you accept everything below.

## 1. No warranty

The Software is provided **"AS IS", WITHOUT WARRANTY OF ANY KIND**, express or
implied, including but not limited to the warranties of merchantability, fitness
for a particular purpose and noninfringement. In no event shall the author or
copyright holder be liable for any claim, damages or other liability, whether in an
action of contract, tort or otherwise, arising from, out of or in connection with
the Software or its use. See [LICENSE](LICENSE).

**You run this at your own risk.**

## 2. Not from Apple, not notarized, not App Store distributed

The Software is **not distributed through the Mac App Store** and is **not notarized
by Apple**. It is signed only with an ad-hoc signature (`codesign --sign -`) and is
distributed directly by the author.

Consequences you should understand before installing:

- macOS Gatekeeper will warn you, and may refuse to open it on first launch. You
  will have to explicitly allow it in **System Settings → Privacy & Security**.
- The Software has **not been reviewed, vetted, approved or endorsed by Apple**.
- It receives none of the guarantees that App Store review or notarization provide.
- Anyone redistributing it takes on responsibility for what they distribute.

Only install software you obtained from a source you trust, and read the source
before you build it. The full source is in this repository.

## 3. It uses a private Apple API

The **Auto** (sunrise/sunset) feature calls
`SLSSetAppearanceThemeSwitchesAutomatically` and related symbols in the private
`SkyLight` framework. macOS exposes no public API for that setting.

- Private APIs are **undocumented and unsupported**, and Apple may change or remove
  them in any macOS update, without notice.
- The Software resolves these symbols with `dlsym` and degrades to "Auto
  unavailable" rather than crashing if they disappear — but this cannot be
  guaranteed for future macOS versions.
- Software using private APIs **cannot be distributed on the Mac App Store**.

If you are uncomfortable with this, untick nothing — simply do not use Auto; Light
and Dark use only public APIs.

## 4. It modifies other applications' configuration files

This is the Software's entire purpose, but you should know exactly what it touches.
On every theme switch it **writes to files it does not own**:

| Path | What happens |
|---|---|
| `~/.config/alacritty/themes/custom/{light,dark}.toml` | overwritten wholesale |
| `~/.tmux/themes/{light,dark}.conf` | overwritten wholesale |
| `~/.config/nvim/lua/themes/*.lua` | overwritten on install |
| `~/.local/share/nvim/theme_state.txt` | overwritten |
| `~/.config/herdr/config.toml` | edited in place with `sed` |
| `~/.claude/settings.json` | the `theme` value is edited in place |
| `~/.claude/themes/*.json` | overwritten on install |
| `~/.zsh_theme_mode`, `~/.cache/macos_theme_mode` | overwritten |

**Back up these files before your first run.** The Software keeps no backups of its
own beyond the first install, and edits to `herdr/config.toml` and
`settings.json` are performed by in-place `sed`, which cannot be undone.

Anything you hand-edit in the regions it manages **will be lost** on the next
switch. For herdr this is explicitly marked:

```
# >>> ProDev Theme Switcher managed >>>
...
# <<< ProDev Theme Switcher managed <<<
```

Edit the theme files in `config/themes/<slug>/` instead, and re-run
`make install-config`.

## 5. It controls system appearance and requires automation permission

The Software changes the **macOS system-wide light/dark appearance** via AppleScript
to System Events. macOS will ask you to grant automation permission on first use.
Denying it leaves the rest of the targets working and only macOS unthemed — or you
can untick **macOS** in the panel.

## 6. Third-party names, themes and trademarks

The author is **not affiliated with, endorsed by, or sponsored by** any of the
following. All product names, logos and trademarks are the property of their
respective owners, and are used here only to describe interoperability:

Apple, macOS, Xcode · Anthropic, Claude, Claude Code · Alacritty · tmux · Neovim ·
herdr · Microsoft, Visual Studio Code · GitHub

The bundled palettes are **derived from third-party themes**, used under their own
licenses and credited to their authors:

| Theme | Author | Upstream |
|---|---|---|
| Tokyo Night (Storm) | Folke Lemaitre | <https://github.com/folke/tokyonight.nvim> (MIT) |
| Rosé Pine (Dawn) | Rosé Pine | <https://rosepinetheme.com> (MIT) |

Colour values have been **modified** from their canonical palettes for contrast and
surface-role reasons documented in the README. These are adaptations; do not treat
them as the upstream themes, and do not report issues with them upstream.

The MIT license in [LICENSE](LICENSE) covers this Software's own code. It does not
grant you rights in any third-party trademark.

## 7. Interoperability, not endorsement

The Software writes configuration for other tools by reading their documented (and,
for herdr and Claude Code, **undocumented**) formats. Those formats can change at any
time, in which case the Software may write configuration that the target rejects or
misinterprets. It is not a supported integration with any of these projects, and
none of them have reviewed it.

## 8. Accessibility claims

The palette gate in `tests/palette_gate.py` checks contrast ratios against specific
numeric thresholds. That is a **useful signal, not a conformance claim**. Passing it
does **not** mean any theme meets WCAG, Section 508, EN 301 549 or any other
accessibility standard. Terminal rendering, font weight, display calibration and
user configuration all affect legibility in ways an automated ratio cannot capture.
If you have specific accessibility needs, verify the result yourself.

## 9. No support obligation

This is a personal project published as-is. There is no service level, no support
commitment, no security response process, and no guarantee of future maintenance,
compatibility or updates.
