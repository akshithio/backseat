import AppKit

/// Which windows are the agent's: ones its own commands opened, and every
/// window of an app it launched. Everything else on the Mac is the user's.
///
/// Acting in one of the user's windows, or in whatever window the user is
/// working in right now, is refused unless the agent says the user asked for
/// it (`user_window: true`). Apps can move things between windows under the
/// agent (a browser whose windows share tabs, say); the agent must never end
/// up driving the user's window because of it.
final class Ownership: @unchecked Sendable {
    static let shared = Ownership()
    private let lock = NSLock()
    private var windows: Set<CGWindowID> = []
    private var apps: Set<pid_t> = []

    func claim(_ ids: [CGWindowID]) {
        lock.lock(); windows.formUnion(ids); lock.unlock()
    }

    func claimApp(_ pid: pid_t) {
        lock.lock(); apps.insert(pid); lock.unlock()
    }

    func owns(_ id: CGWindowID, pid: pid_t) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return windows.contains(id) || apps.contains(pid)
    }

    /// The window the user is in right now, if it belongs to `pid`.
    static func userWindow(pid: pid_t) -> CGWindowID? {
        guard NSRunningApplication(processIdentifier: pid)?.isActive == true else { return nil }
        return AX.attr(AX.app(pid), kAXFocusedWindowAttribute).map { $0 as! AXUIElement }.flatMap(AX.windowID)
    }

    /// Throws unless the agent may act in (or, with `reading`, read) window
    /// `id` of `pid`. A nil window means the app's focused element.
    static func check(window id: CGWindowID?, pid: pid_t, _ args: Args, reading: Bool = false) throws {
        if args.bool("user_window") == true { return }
        let app = NSRunningApplication(processIdentifier: pid)
        let name = app?.localizedName ?? "the app"
        let own = "Work in a window of your own: open one (select_menu_item File > New Window, or launch_app with a url) and use its id. Pass user_window: true only if the user asked you to use their window."
        guard let id else {
            if !reading, app?.isActive == true {
                throw ToolError("the user is working in \(name) right now, so its focused element is theirs; nothing was sent. \(own)")
            }
            return
        }
        if id == userWindow(pid: pid) {
            throw ToolError("window \(id) is the one the user is working in right now, so \(reading ? "it wasn't read" : "nothing was done"). \(own)")
        }
        if !reading, !shared.owns(id, pid: pid) {
            throw ToolError("window \(id) is one of the user's \(name) windows (you didn't open it), so nothing was done. \(own)")
        }
    }

    /// The window an element is in.
    static func window(of e: AXUIElement) -> CGWindowID? {
        AX.containingWindow(e).flatMap(AX.windowID)
    }
}
