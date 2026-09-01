import AppKit
import ServiceManagement

// NG-Thm-Ch — one-click Tokyo Night Storm / Rosé Pine Dawn across macOS + terminal tools.
//
// The macOS appearance is the single source of truth. This app flips it, then reacts to
// AppleInterfaceThemeChangedNotification and shells out to ~/.config/theme-sync-all.sh,
// which already knows how to theme Alacritty, tmux, Neovim, herdr and the zsh prompt.
// Switching from Control Center or the auto sunset schedule therefore works for free.

// MARK: - Model

enum Mode: String {
    case dark, light
    var flipped: Mode { self == .dark ? .light : .dark }
    var symbol: String { self == .dark ? "moon.stars.fill" : "sun.max.fill" }
    var title: String { self == .dark ? "Dark" : "Light" }
    var theme: String { self == .dark ? "Tokyo Night Storm" : "Rosé Pine Dawn" }
}

/// Targets the menu can opt out of. rawValue is the token passed in NGTHMCH_SKIP.
enum Target: String, CaseIterable {
    case macos, alacritty, nvim, tmux, herdr, claude

    var label: String {
        switch self {
        case .macos:     return "macOS"
        case .alacritty: return "Alacritty"
        case .nvim:      return "Neovim"
        case .tmux:      return "tmux"
        case .herdr:     return "herdr"
        case .claude:    return "Claude Code"
        }
    }
    private var key: String { "skip.\(rawValue)" }
    var enabled: Bool {
        get { !UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(!newValue, forKey: key) }
    }
}

let syncScript = NSHomeDirectory() + "/.config/theme-sync-all.sh"

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
                + NSHomeDirectory() + "/.local/bin"
    env["NGTHMCH_SKIP"] = Target.allCases.filter { !$0.enabled }
                                         .map(\.rawValue).joined(separator: ",")

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [syncScript, "--quiet", m.rawValue]
    p.environment = env
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
}

func toggle() {
    if Target.macos.enabled {
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
        if Target.macos.enabled { setAutoAppearance(false); setSystemMode(m) }
        applyToApps(m)
    default:
        FileHandle.standardError.write("usage: ng-thm-ch --set dark|light|auto|toggle\n".data(using: .utf8)!)
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
        }
    }

    private func refreshIcon() {
        let m = systemMode()
        let auto = autoAppearance()
        let img = NSImage(systemSymbolName: auto ? "circle.lefthalf.filled" : m.symbol,
                          accessibilityDescription: m.title)
        img?.isTemplate = true
        item.button?.image = img
        item.button?.toolTip = "NG-Thm-Ch — \(m.theme)" + (auto ? " (Auto)" : "")
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
        let header = NSMenuItem(title: "\(m.title) — \(m.theme)", action: nil, keyEquivalent: "")
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

        for t in Target.allCases {
            let i = NSMenuItem(title: t.label, action: #selector(toggleTarget(_:)), keyEquivalent: "")
            i.target = self
            i.state = t.enabled ? .on : .off
            i.representedObject = t.rawValue
            menu.addItem(i)
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

        let quit = NSMenuItem(title: "Quit NG-Thm-Ch", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
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

    @objc private func toggleTarget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, var t = Target(rawValue: raw) else { return }
        t.enabled.toggle()
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
