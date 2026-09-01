import Foundation
import ThemeSwitcherCore

// Covers every branch in ThemeSwitcherCore. The AppKit glue in main.swift is not
// covered and cannot be: NSStatusItem, AppleScript and the SkyLight dlsym calls all
// need a window server. That boundary is why the model lives in its own target.

// MARK: - Mode

T.suite("Mode") {
    T.eq(Mode.dark.flipped, .light, "dark flips")
    T.eq(Mode.light.flipped, .dark, "light flips")
    T.eq(Mode.allCases.count, 2, "two modes")
    T.eq(Mode.dark.title, "Dark", "dark title")
    T.eq(Mode.light.title, "Light", "light title")
    T.eq(Mode.dark.symbol, "moon.stars.fill", "dark symbol")
    T.eq(Mode.light.symbol, "sun.max.fill", "light symbol")
    T.eq(Mode.dark.prefsKey, "theme.dark", "dark prefs key")
    T.eq(Mode.light.prefsKey, "theme.light", "light prefs key")
    T.eq(Mode.dark.defaultSlug, "tokyo-night-storm", "shipped dark theme")
    T.eq(Mode.light.defaultSlug, "rose-pine-dawn", "shipped light theme")
    // sync.sh reads exactly these names. A rename on either side breaks the handoff
    // silently, because the script just falls back to its own default.
    T.eq(Mode.light.themeEnvKey, "PDTS_LIGHT_THEME", "light env key")
    T.eq(Mode.dark.themeEnvKey, "PDTS_DARK_THEME", "dark env key")
    T.nilCheck(Mode(rawValue: "sepia"), "unknown mode")
}

// MARK: - meta parsing

T.suite("parseMeta") {
    let f = Theme.parseMeta("mode=light\nname=Rosé Pine Dawn\nnvim=rose-pine-dawn\n")
    T.eq(f["mode"], "light", "mode")
    T.eq(f["name"], "Rosé Pine Dawn", "name survives non-ascii")
    T.eq(f["nvim"], "rose-pine-dawn", "per-target id")

    T.eq(Theme.parseMeta("\n# a comment\nmode=dark\ngarbage\n=novalue\n  \n"),
         ["mode": "dark"], "blanks, comments and malformed lines ignored")
    T.eq(Theme.parseMeta("accent=#69=54=82")["accent"], "#69=54=82", "value may contain =")
    T.eq(Theme.parseMeta("  mode = dark  ")["mode"], "dark", "whitespace trimmed")
    T.eq(Theme.parseMeta(""), [:], "empty input")
}

T.suite("Theme.make") {
    T.eq(Theme.make(slug: "some-theme", meta: "mode=dark")?.name, "some-theme",
         "name falls back to slug")
    T.eq(Theme.make(slug: "x", meta: "mode=dark")?.mode, .dark, "mode parsed")
    T.eq(Theme.make(slug: "tokyo-night-storm", meta: "mode=dark\nherdr=tokyo-night\n")?
            .fields["herdr"], "tokyo-night", "per-target fields kept")
    // A theme with no usable mode belongs in neither submenu, so it is dropped
    // rather than defaulted into one.
    T.nilCheck(Theme.make(slug: "x", meta: "name=No Mode"), "missing mode")
    T.nilCheck(Theme.make(slug: "x", meta: "mode=sepia"), "unknown mode")
}

// MARK: - loading from disk

T.suite("Theme.load") {
    let fm = FileManager.default
    let root = NSTemporaryDirectory() + "pdts-\(UUID().uuidString)"
    defer { try? fm.removeItem(atPath: root) }

    func write(_ slug: String, _ meta: String?) throws {
        try fm.createDirectory(atPath: "\(root)/\(slug)", withIntermediateDirectories: true)
        if let meta { try meta.write(toFile: "\(root)/\(slug)/meta", atomically: true, encoding: .utf8) }
    }

    try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
    try write("zulu", "mode=dark\nname=Zulu")
    try write("alpha", "mode=light\nname=Alpha")
    // A half-copied directory should cost that one theme, not the whole menu.
    try write("no-meta", nil)
    try write("bad-meta", "nothing useful here")

    let all = Theme.load(root: root)
    T.eq(all.map(\.slug), ["alpha", "zulu"], "sorted, unusable entries skipped")
    T.eq(Theme.forMode(.dark, in: all).map(\.slug), ["zulu"], "dark submenu")
    T.eq(Theme.forMode(.light, in: all).map(\.slug), ["alpha"], "light submenu")
    T.eq(Theme.load(root: root + "/nope"), [], "missing root is empty, not a crash")
    T.ok(!Theme.defaultRoot.isEmpty, "default root resolves")
    T.ok(Theme.defaultRoot.hasSuffix("/.config/prodev-theme-switcher/themes"), "default root path")
}

// MARK: - targets

T.suite("Target") {
    T.eq(Target.allCases.count, 6, "six targets")
    for t in Target.allCases {
        T.ok(!t.label.isEmpty, "\(t.rawValue) has a label")
        T.eq(t.prefsKey, "skip.\(t.rawValue)", "\(t.rawValue) prefs key")
    }
    T.eq(Target.macos.label, "macOS", "macos label")
    T.eq(Target.alacritty.label, "Alacritty", "alacritty label")
    T.eq(Target.nvim.label, "Neovim", "nvim label")
    T.eq(Target.tmux.label, "tmux", "tmux label")
    T.eq(Target.herdr.label, "herdr", "herdr label")
    T.eq(Target.claude.label, "Claude Code", "claude label")

    T.eq(Target.skipList(disabled: []), "", "nothing disabled")
    // Built from allCases rather than the Set, so the value does not churn between
    // runs purely because Set iteration order changed.
    T.eq(Target.skipList(disabled: [.claude, .macos, .nvim]), "macos,nvim,claude", "declaration order")
    T.eq(Target.skipList(disabled: Set(Target.allCases)),
         "macos,alacritty,nvim,tmux,herdr,claude", "all disabled")
}

// MARK: - selection

/// Stands in for UserDefaults so selections never touch the real prefs domain.
final class MemoryStore: PreferenceStore {
    var strings: [String: String] = [:]
    var bools: [String: Bool] = [:]
    func string(for key: String) -> String? { strings[key] }
    func setString(_ value: String, for key: String) { strings[key] = value }
    func bool(for key: String) -> Bool { bools[key] ?? false }
    func setBool(_ value: Bool, for key: String) { bools[key] = value }
}

T.suite("Selection") {
    let store = MemoryStore()
    let sel = Selection(store: store)

    T.eq(sel.slug(for: .dark), "tokyo-night-storm", "dark default")
    T.eq(sel.slug(for: .light), "rose-pine-dawn", "light default")

    sel.setSlug("something-else", for: .light)
    T.eq(sel.slug(for: .light), "something-else", "light picked")
    T.eq(sel.slug(for: .dark), "tokyo-night-storm", "other mode untouched")

    for t in Target.allCases { T.ok(sel.isEnabled(t), "\(t.rawValue) enabled by default") }
    T.ok(sel.disabledTargets.isEmpty, "nothing disabled by default")

    // Stored inverted: an absent key must read as enabled, so a fresh install
    // themes everything rather than nothing.
    sel.setEnabled(false, for: .herdr)
    T.ok(!sel.isEnabled(.herdr), "herdr disabled")
    T.eq(sel.disabledTargets, [.herdr], "disabled set")
    T.eq(store.bools["skip.herdr"], true, "persisted inverted")
    sel.setEnabled(true, for: .herdr)
    T.ok(sel.isEnabled(.herdr), "herdr re-enabled")
    T.ok(sel.disabledTargets.isEmpty, "disabled set cleared")

    let themes = [Theme(slug: "rose-pine-dawn", name: "Rosé Pine Dawn", mode: .light)]
    sel.setSlug("rose-pine-dawn", for: .light)
    T.eq(sel.displayName(for: .light, in: themes), "Rosé Pine Dawn", "display name")
    // The chosen theme's directory can be deleted after it was picked; the menu
    // should still say something rather than render blank.
    sel.setSlug("deleted-theme", for: .dark)
    T.eq(sel.displayName(for: .dark, in: []), "deleted-theme", "falls back to slug")

    sel.setSlug("my-light", for: .light)
    sel.setEnabled(false, for: .tmux)
    let env = sel.environment()
    T.eq(env["PDTS_LIGHT_THEME"], "my-light", "env light")
    T.eq(env["PDTS_DARK_THEME"], "deleted-theme", "env dark")
    T.eq(env["PDTS_SKIP"], "tmux", "env skip")
    T.eq(env.count, 3, "env has no extras")

    T.eq(Theme(slug: "a", name: "A", mode: .dark), Theme(slug: "a", name: "A", mode: .dark),
         "themes compare by value")
}

// The UserDefaults conformance is the seam the real app runs through, so it is
// exercised against a throwaway suite rather than the app's own prefs domain.
T.suite("UserDefaults conformance") {
    let suiteName = "pdts-tests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        T.fail("could not create a scratch defaults suite"); return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store: PreferenceStore = defaults
    T.nilCheck(store.string(for: "theme.light"), "absent key reads nil")
    T.ok(!store.bool(for: "skip.tmux"), "absent bool reads false")

    store.setString("rose-pine-dawn", for: "theme.light")
    store.setBool(true, for: "skip.tmux")
    T.eq(store.string(for: "theme.light"), "rose-pine-dawn", "string round-trips")
    T.eq(store.bool(for: "skip.tmux"), true, "bool round-trips")

    // Same object, driven through Selection the way the app drives it.
    let sel = Selection(store: defaults)
    T.eq(sel.slug(for: .light), "rose-pine-dawn", "selection reads it back")
    T.ok(!sel.isEnabled(.tmux), "selection sees the skip")
}

T.report()
