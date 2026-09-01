import AppKit
import ServiceManagement
import ThemeSwitcherCore

// ProDev Theme Switcher — one click, every tool, one theme.
//
// The macOS appearance is the single source of truth. This app flips it, then reacts to
// AppleInterfaceThemeChangedNotification and shells out to sync.sh, which knows how to
// theme Alacritty, tmux, Neovim, herdr, Claude Code and the zsh prompt. Switching from
// Control Center or the auto sunset schedule therefore works for free.
//
// Themes are directories on disk, not code: the menu lists whatever is in
// ~/.config/prodev-theme-switcher/themes, so adding one needs no rebuild.

// MARK: - Model
//
// Mode, Theme, Target and Selection live in ThemeSwitcherCore: pure Foundation, so
// CI can cover them without a window server. Everything below this point is AppKit
// glue that only runs on a real desktop.

let prefs = Selection(store: UserDefaults.standard,
                      environment: ProcessInfo.processInfo.environment)
var installedThemes: [Theme] { Theme.load(root: Theme.defaultRoot) }

/// Re-probed every time the menu opens and on every apply, so installing a tool and
/// reopening the menu is enough to pick it up -- no watcher, no restart.
var installedTargets: Set<Target> { Detection.installed(home: Paths.home()) }

let syncScript = Paths.root() + "/sync.sh"

// MARK: - Auto appearance (sunrise/sunset)

// macOS exposes no public API for the Auto appearance mode. System Settings drives it
// through these SkyLight entry points; all four verified present on macOS 27. If a
// future OS drops them, dlsym returns nil and Auto degrades to unavailable rather
// than crashing.
private let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

var autoAppearanceAvailable: Bool {
    dlsym(skyLight, "SLSSetAppearanceThemeSwitchesAutomatically") != nil
}

func autoAppearance() -> Bool {
    typealias Get = @convention(c) () -> Bool
    guard let f = dlsym(skyLight, "SLSGetAppearanceThemeSwitchesAutomatically") else { return false }
    return unsafeBitCast(f, to: Get.self)()
}

func setAutoAppearance(_ on: Bool) {
    typealias Set = @convention(c) (Bool) -> Void
    guard let f = dlsym(skyLight, "SLSSetAppearanceThemeSwitchesAutomatically") else { return }
    unsafeBitCast(f, to: Set.self)(on)
}

// MARK: - System appearance

/// Read straight from CFPreferences so it is fresh even moments after a change,
/// and so it works on the --set CLI path where there is no NSApp.
func systemMode() -> Mode {
    CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
    let v = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString,
                                      kCFPreferencesAnyApplication) as? String
    return v == "Dark" ? .dark : .light
}

func setSystemMode(_ m: Mode) {
    let src = """
    tell application "System Events" to tell appearance preferences \
    to set dark mode to \(m == .dark)
    """
    var err: NSDictionary?
    NSAppleScript(source: src)?.executeAndReturnError(&err)
    if let err { FileHandle.standardError.write("AppleScript: \(err)\n".data(using: .utf8)!) }
}

// MARK: - Propagation

/// The only place themes get written. Deliberately delegates to theme-sync-all.sh
/// rather than reimplementing it, so the menu bar and the shell/keybindings stay
/// on one code path.
func applyToApps(_ m: Mode) {
    UserDefaults.standard.set(m.rawValue, forKey: "mode")

    var env = ProcessInfo.processInfo.environment
    // A GUI app does not inherit the login shell PATH; the script calls tmux/herdr bare.
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:"
                + Paths.home() + "/.local/bin"
    // Uninstalled tools are skipped as well as user-unticked ones: writing config
    // for something that is not there is how you leave files behind for a tool the
    // user never had.
    for (k, v) in prefs.environment(installed: installedTargets) { env[k] = v }

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [syncScript, "--quiet", m.rawValue]
    p.environment = env
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
}

func toggle() {
    if prefs.isEnabled(.macos, installed: installedTargets) {
        setAutoAppearance(false)              // an explicit pick leaves Auto, as in System Settings
        setSystemMode(systemMode().flipped)   // observer fires applyToApps
    } else {
        let last = UserDefaults.standard.string(forKey: "mode").flatMap(Mode.init) ?? systemMode()
        applyToApps(last.flipped)
    }
}

// MARK: - CLI (headless, for check.sh and keybindings)

let argv = CommandLine.arguments
if let i = argv.firstIndex(of: "--set"), i + 1 < argv.count {
    switch argv[i + 1] {
    case "toggle": toggle()
    case "auto":
        setAutoAppearance(true)
        Thread.sleep(forTimeInterval: 0.4)
        applyToApps(systemMode())
    case let s where Mode(rawValue: s) != nil:
        let m = Mode(rawValue: s)!
        if prefs.isEnabled(.macos, installed: installedTargets) { setAutoAppearance(false); setSystemMode(m) }
        applyToApps(m)
    default:
        FileHandle.standardError.write("usage: prodev-theme-switcher --set dark|light|auto|toggle\n".data(using: .utf8)!)
        exit(2)
    }
    Thread.sleep(forTimeInterval: 1.2)   // let the spawned script finish before we exit
    exit(0)
}

// MARK: - Menu bar

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(click)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refreshIcon()

        DistributedNotificationCenter.default().addObserver(
            forName: .init("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            applyToApps(systemMode())
            self?.refreshIcon()
        }

        // Register once, on first ever launch. Re-registering every launch would
        // silently undo the user unticking "Launch at Login".
        if !UserDefaults.standard.bool(forKey: "didFirstRun") {
            UserDefaults.standard.set(true, forKey: "didFirstRun")
            try? SMAppService.mainApp.register()
            warnIfNothingToTheme()
        }
    }

    /// Said once, on first launch only. With nothing but macOS installed the app
    /// still works, but it is switching one thing -- and a menu bar icon that
    /// appears to do almost nothing is worse than being told why.
    private func warnIfNothingToTheme() {
        guard Detection.onlyMacOS(installedTargets) else { return }
        let a = NSAlert()
        a.messageText = "No supported apps found"
        a.informativeText = """
            ProDev Theme Switcher will switch the macOS appearance, but it found none \
            of the tools it themes: Alacritty, Neovim, tmux, herdr or Claude Code.

            Install any of them and reopen the menu — they are detected automatically, \
            with no restart.
            """
        a.alertStyle = .informational
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    private func refreshIcon() {
        let m = systemMode()
        let auto = autoAppearance()
        let img = NSImage(systemSymbolName: auto ? "circle.lefthalf.filled" : m.symbol,
                          accessibilityDescription: m.title)
        img?.isTemplate = true
        item.button?.image = img
        item.button?.toolTip = "ProDev Theme Switcher — \(prefs.displayName(for: m, in: installedThemes))" + (auto ? " (Auto)" : "")
    }

    @objc private func click() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            item.menu = buildMenu()
            item.button?.performClick(nil)
            item.menu = nil                 // restore left-click-to-toggle
        } else {
            toggle()
            refreshIcon()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let m = systemMode()

        let auto = autoAppearance()
        let header = NSMenuItem(title: "\(m.title) — \(prefs.displayName(for: m, in: installedThemes))",
                               action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Light / Dark / Auto. Auto hands control to the macOS sunrise/sunset schedule;
        // the app keeps syncing because it listens for the appearance notification.
        let picks: [(String, String, Bool, Selector)] = [
            ("Light", "sun.max",               !auto && m == .light, #selector(pickLight)),
            ("Dark",  "moon.stars",            !auto && m == .dark,  #selector(pickDark)),
            ("Auto",  "clock.arrow.2.circlepath", auto,              #selector(pickAuto)),
        ]
        for (title, sym, on, sel) in picks {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            i.state = on ? .on : .off
            i.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil)
            if title == "Auto" {
                i.isEnabled = autoAppearanceAvailable
                i.toolTip = "Follow the macOS sunrise/sunset schedule"
            }
            menu.addItem(i)
        }
        menu.addItem(.separator())

        // One submenu per mode, listing every installed theme for it. Picking the
        // theme for the mode you are already in re-applies immediately; picking for
        // the other mode just records it, so nothing flashes.
        for mode in [Mode.light, .dark] {
            let item = NSMenuItem(title: "\(mode.title) Theme", action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: mode.symbol.replacingOccurrences(of: ".fill", with: ""),
                                 accessibilityDescription: nil)
            let sub = NSMenu()
            let themes = Theme.forMode(mode, in: installedThemes)
            if themes.isEmpty {
                let none = NSMenuItem(title: "None installed", action: nil, keyEquivalent: "")
                none.isEnabled = false
                sub.addItem(none)
            }
            for t in themes {
                let ti = NSMenuItem(title: t.name, action: #selector(pickTheme(_:)), keyEquivalent: "")
                ti.target = self
                ti.state = t.slug == prefs.slug(for: mode) ? .on : .off
                ti.representedObject = [mode.rawValue, t.slug]
                sub.addItem(ti)
            }
            item.submenu = sub
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // Only what is actually on this machine gets a working switch. Everything
        // else is listed disabled rather than hidden, so it is obvious the app
        // supports it and equally obvious why it is not doing anything.
        let installed = installedTargets
        for t in Target.allCases {
            let here = installed.contains(t)
            let i = NSMenuItem(title: here ? t.label : "\(t.label) — not installed",
                               action: here ? #selector(toggleTarget(_:)) : nil,
                               keyEquivalent: "")
            i.target = self
            i.isEnabled = here
            i.state = prefs.isEnabled(t, installed: installed) ? .on : .off
            i.representedObject = t.rawValue
            menu.addItem(i)
        }
        if Detection.onlyMacOS(installed) {
            let note = NSMenuItem(title: "No supported apps found — macOS only",
                                  action: nil, keyEquivalent: "")
            note.isEnabled = false
            note.toolTip = "Install Alacritty, Neovim, tmux, herdr or Claude Code and "
                         + "reopen this menu; they are picked up automatically."
            menu.addItem(note)
        }
        // VS Code follows the OS on its own via window.autoDetectColorScheme, so this
        // app never touches it. Shown disabled rather than as a checkbox that would lie.
        let vsc = NSMenuItem(title: "VS Code — follows macOS", action: nil, keyEquivalent: "")
        vsc.isEnabled = false
        menu.addItem(vsc)

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "Quit ProDev Theme Switcher", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    @objc private func pickLight() { setAutoAppearance(false); setSystemMode(.light); refreshIcon() }
    @objc private func pickDark()  { setAutoAppearance(false); setSystemMode(.dark);  refreshIcon() }

    @objc private func pickAuto() {
        setAutoAppearance(true)
        // If Auto resolves to the mode we are already in, macOS posts no appearance
        // notification, so sync once explicitly rather than silently doing nothing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            applyToApps(systemMode())
            self?.refreshIcon()
        }
    }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let mode = Mode(rawValue: pair[0]) else { return }
        prefs.setSlug(pair[1], for: mode)
        // Only repaint if this is the mode currently on screen.
        if mode == systemMode() { applyToApps(mode) }
        refreshIcon()
    }

    @objc private func toggleTarget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let t = Target(rawValue: raw) else { return }
        prefs.setEnabled(!prefs.isEnabled(t), for: t)
    }

    @objc private func toggleLogin() {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        else { try? SMAppService.mainApp.register() }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
