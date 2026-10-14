import Foundation
import MCP

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Typed access to a tool call's arguments.
struct Args {
    let raw: [String: Value]

    init(_ raw: [String: Value]?) { self.raw = raw ?? [:] }

    func string(_ key: String) -> String? { raw[key]?.stringValue }

    func number(_ key: String) -> Double? {
        guard let v = raw[key] else { return nil }
        if let d = v.doubleValue { return d }
        if let i = v.intValue { return Double(i) }
        if let s = v.stringValue { return Double(s) }
        return nil
    }

    func int(_ key: String) -> Int? { number(key).map { Int($0) } }

    func bool(_ key: String) -> Bool? {
        guard let v = raw[key] else { return nil }
        if let b = v.boolValue { return b }
        if let s = v.stringValue { return s == "true" }
        return nil
    }

    func strings(_ key: String) -> [String]? {
        raw[key]?.arrayValue?.compactMap(\.stringValue)
    }

    func require<T>(_ key: String, _ get: (String) -> T?) throws -> T {
        guard let v = get(key) else { throw ToolError("missing required argument '\(key)'") }
        return v
    }
}

/// Lets exactly one of several racing callers win.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

/// Runs `body`, giving up after `seconds`. Answers the caller either way, even
/// if `body` is stuck in a system call that ignores cancellation (a task group
/// would wait for it), so a stuck call can't hang a tool.
func withTimeout<T: Sendable>(seconds: Double, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    let once = Once()
    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
        let work = Task {
            do {
                let value = try await body()
                if once.claim() { cont.resume(returning: value) }
            } catch {
                if once.claim() { cont.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if once.claim() {
                work.cancel()
                cont.resume(throwing: ToolError("timed out after \(Int(seconds))s"))
            }
        }
    }
}
