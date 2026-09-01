import Foundation

// A 40-line runner instead of XCTest: XCTest needs a full Xcode install and an
// accepted licence, which a Command Line Tools box does not have. This runs
// anywhere the package builds, including CI, and exits non-zero on failure.

enum T {
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var checks = 0
    nonisolated(unsafe) static var current = ""

    static func suite(_ name: String, _ body: () throws -> Void) {
        current = name
        do { try body() } catch { fail("threw \(error)") }
    }

    static func fail(_ message: String, _ line: UInt = #line) {
        failures.append("\(current):\(line)  \(message)")
    }

    static func ok(_ condition: Bool, _ what: String, _ line: UInt = #line) {
        checks += 1
        if !condition { fail("expected \(what)", line) }
    }

    static func eq<V: Equatable>(_ got: V, _ want: V, _ what: String, _ line: UInt = #line) {
        checks += 1
        if got != want { fail("\(what): got \(got), want \(want)", line) }
    }

    static func nilCheck<V>(_ got: V?, _ what: String, _ line: UInt = #line) {
        checks += 1
        if got != nil { fail("\(what): expected nil, got \(got!)", line) }
    }

    static func report() -> Never {
        if failures.isEmpty {
            print("\u{001B}[32m✓\u{001B}[0m \(checks) checks passed")
            exit(0)
        }
        for f in failures { print("\u{001B}[31m✗\u{001B}[0m \(f)") }
        print("\n\(failures.count) of \(checks) checks failed")
        exit(1)
    }
}
