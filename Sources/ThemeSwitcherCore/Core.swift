import Foundation

// Everything here is pure Foundation and free of AppKit, so it runs on a headless
// CI box. The AppKit glue in main.swift cannot be exercised without a window server;
// keeping the decisions on this side of the line is what makes them testable at all.

/// Light or dark. macOS appearance is the source of truth for which one is active;
/// this type only knows how to describe and pair them.
public enum Mode: String, CaseIterable, Sendable {
    case dark, light

    public var flipped: Mode { self == .dark ? .light : .dark }
    public var title: String { self == .dark ? "Dark" : "Light" }
    public var symbol: String { self == .dark ? "moon.stars.fill" : "sun.max.fill" }

    /// Theme each mode falls back to when nothing has been chosen.
    public var defaultSlug: String {
        self == .dark ? "tokyo-night-storm" : "rose-pine-dawn"
    }
    /// Env var the sync script reads for this mode's selection.
    public var themeEnvKey: String { "PDTS_\(rawValue.uppercased())_THEME" }
    public var prefsKey: String { "theme.\(rawValue)" }
}

/// A theme is a directory containing one file per target plus a `meta` file. The
/// menu is built from whatever is installed, so adding a theme is adding a folder.
public struct Theme: Equatable, Sendable {
    public let slug: String
    public let name: String
    public let mode: Mode
    /// Per-target identifiers. A slug is not always what a target calls the same
    /// theme: tokyo-night-storm is `tokyonight-storm` to base46, `tokyo-night` to herdr.
    public let fields: [String: String]

    public init(slug: String, name: String, mode: Mode, fields: [String: String] = [:]) {
        self.slug = slug; self.name = name; self.mode = mode; self.fields = fields
    }

    /// `key=value` per line. Unknown keys are kept, blank lines and lines without a
    /// separator are ignored, and a value may itself contain `=`.
    public static func parseMeta(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            out[key] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    /// Nil when the meta file names no mode, or a mode this build does not know.
    /// A theme without a usable mode cannot be offered in either submenu.
    public static func make(slug: String, meta: String) -> Theme? {
        let fields = parseMeta(meta)
        guard let raw = fields["mode"], let mode = Mode(rawValue: raw) else { return nil }
        return Theme(slug: slug, name: fields["name"] ?? slug, mode: mode, fields: fields)
    }

    /// Scans `root` for theme directories, sorted by slug so the menu is stable.
    /// Directories without a readable `meta` are skipped rather than failing the load.
    public static func load(root: String, fs: FileManager = .default) -> [Theme] {
        let entries = (try? fs.contentsOfDirectory(atPath: root)) ?? []
        return entries.sorted().compactMap { slug in
            guard let meta = try? String(contentsOfFile: "\(root)/\(slug)/meta", encoding: .utf8)
            else { return nil }
            return make(slug: slug, meta: meta)
        }
    }

    /// Where `make install-config` puts them.
    public static var defaultRoot: String { Paths.root() + "/themes" }

    public static func forMode(_ mode: Mode, in themes: [Theme]) -> [Theme] {
        themes.filter { $0.mode == mode }
    }
}

/// Targets the menu can opt out of. rawValue is the token passed in PDTS_SKIP.
public enum Target: String, CaseIterable, Sendable {
    case macos, alacritty, nvim, tmux, herdr, claude

    public var label: String {
        switch self {
        case .macos:     return "macOS"
        case .alacritty: return "Alacritty"
        case .nvim:      return "Neovim"
        case .tmux:      return "tmux"
        case .herdr:     return "herdr"
        case .claude:    return "Claude Code"
        }
    }
    public var prefsKey: String { "skip.\(rawValue)" }

    /// Env var holding a comma list of targets to leave alone for one invocation.
    public static let skipEnvKey = "PDTS_SKIP"

    /// Parses that list. Unknown tokens are ignored rather than rejected, so a
    /// typo costs that one target rather than the whole run.
    public static func parseSkipList(_ raw: String?) -> Set<Target> {
        Set((raw ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap(Target.init(rawValue:)))
    }

    /// Comma list the sync script parses. Order follows allCases so the value is
    /// stable across runs rather than reflecting Set iteration order.
    public static func skipList(disabled: Set<Target>) -> String {
        allCases.filter { disabled.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
}

/// Where the app keeps sync.sh and the themes.
///
/// Resolved from HOME rather than NSHomeDirectory(), which consults the password
/// database and so can ignore an overridden HOME -- that makes the app untestable
/// against a scratch home, which is exactly what CI needs to do.
public enum Paths {
    public static func home(_ environment: [String: String] = ProcessInfo.processInfo.environment,
                            fallback: String = NSHomeDirectory()) -> String {
        let h = environment["HOME"] ?? ""
        return h.isEmpty ? fallback : h
    }
    public static func root(_ environment: [String: String] = ProcessInfo.processInfo.environment,
                            fallback: String = NSHomeDirectory()) -> String {
        home(environment, fallback: fallback) + "/.config/prodev-theme-switcher"
    }
}

/// Minimal key-value store so selections can be exercised without UserDefaults.
public protocol PreferenceStore: AnyObject {
    func string(for key: String) -> String?
    func setString(_ value: String, for key: String)
    func bool(for key: String) -> Bool
    func setBool(_ value: Bool, for key: String)
}

extension UserDefaults: PreferenceStore {
    public func string(for key: String) -> String? { string(forKey: key) }
    public func setString(_ value: String, for key: String) { set(value, forKey: key) }
    public func bool(for key: String) -> Bool { bool(forKey: key) }
    public func setBool(_ value: Bool, for key: String) { set(value, forKey: key) }
}

/// The app's persisted choices. Holds every decision the menu makes, so the menu
/// itself stays a rendering of this and nothing more.
public final class Selection {
    private let store: PreferenceStore
    /// Targets skipped for this invocation only, from PDTS_SKIP. The menu writes
    /// its choices to the store; the environment overrides them without persisting,
    /// matching how PDTS_LIGHT_THEME / PDTS_DARK_THEME already behave. Without this
    /// the variable was write-only -- emitted for sync.sh, never honoured by the
    /// app itself, so `PDTS_SKIP=macos ... --set light` still drove the appearance.
    private let envSkips: Set<Target>

    public init(store: PreferenceStore, environment: [String: String] = [:]) {
        self.store = store
        self.envSkips = Target.parseSkipList(environment[Target.skipEnvKey])
    }

    public func slug(for mode: Mode) -> String {
        store.string(for: mode.prefsKey) ?? mode.defaultSlug
    }
    public func setSlug(_ slug: String, for mode: Mode) {
        store.setString(slug, for: mode.prefsKey)
    }
    public func isEnabled(_ target: Target) -> Bool {
        !store.bool(for: target.prefsKey) && !envSkips.contains(target)
    }
    public func setEnabled(_ enabled: Bool, for target: Target) {
        store.setBool(!enabled, for: target.prefsKey)
    }
    public var disabledTargets: Set<Target> {
        Set(Target.allCases.filter { !isEnabled($0) })
    }

    /// Display name for a mode's chosen theme, falling back to the slug when the
    /// theme directory has been removed since it was picked.
    public func displayName(for mode: Mode, in themes: [Theme]) -> String {
        let s = slug(for: mode)
        return themes.first { $0.slug == s }?.name ?? s
    }

    /// Environment handed to sync.sh. The script prefers these over its own state
    /// files, so the menu and the CLI cannot disagree about what is selected.
    public func environment() -> [String: String] {
        [
            "PDTS_SKIP": Target.skipList(disabled: disabledTargets),
            Mode.light.themeEnvKey: slug(for: .light),
            Mode.dark.themeEnvKey: slug(for: .dark),
        ]
    }
}
