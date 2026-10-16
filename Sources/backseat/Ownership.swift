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
    /// Apps where a command may have opened a window that hasn't shown up yet.
    private var pending: [pid_t: [(until: Date, before: Set<CGWindowID>)]] = [:]

    /// A command that can open a window in `pid` ran, and none has shown up
    /// yet: count one more for a few seconds, so quick calls can't outrun the
    /// window budget while a slow app is still building the window.
    func expectWindow(pid: pid_t, before: Set<CGWindowID>) {
        lock.lock(); pending[pid, default: []].append((Date().addingTimeInterval(3), before)); lock.unlock()
    }

    func claim(_ ids: [CGWindowID]) {
        lock.lock(); windows.formUnion(ids); lock.unlock()
    }

    /// Windows expected in `pid` that haven't appeared yet.
    private func pendingCount(_ pid: pid_t, open: [WindowInfo]) -> Int {
        lock.lock(); defer { lock.unlock() }
        let live = (pending[pid] ?? []).filter { $0.until > Date() }
        pending[pid] = live
        guard let first = live.first else { return 0 }
        let appeared = open.filter { !first.before.contains($0.id) }.count
        return max(0, live.count - appeared)
    }

    func claimApp(_ pid: pid_t) {
        lock.lock(); apps.insert(pid); lock.unlock()
    }

    /// True if the agent opened window `id` itself (not just any window of an app it launched).
    func ownsWindow(_ id: CGWindowID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return windows.contains(id)
    }

    func owns(_ id: CGWindowID, pid: pid_t) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return windows.contains(id) || apps.contains(pid)
    }

    /// The agent's windows of `pid` that are still open.
    func open(pid: pid_t) -> [WindowInfo] {
        // Accessibility lists real windows (not the hidden ones apps keep
        // around), but can miss one that only just opened; the WindowServer
        // has a window on screen the moment it's shown. Count both.
        // Only windows someone could see count: apps keep helper windows ordered
        // out (Chrome has a couple), on no Space at all. Minimized ones count.
        func real(_ w: WindowInfo) -> Bool {
            w.alpha > 0 && (Windows.hasSpace(w.id)
                || AX.window(id: w.id, pid: pid).map { (AX.attr($0, kAXMinimizedAttribute) as? Bool) == true } == true)
        }
        var all = Windows.list(pid: pid).filter(real)
        let listed = Set(Windows.list(pid: pid).map(\.id))
        all += Windows.all().filter { $0.pid == pid && $0.layer == 0 && !listed.contains($0.id) && real($0) }
        lock.lock(); defer { lock.unlock() }
        return apps.contains(pid) ? all : all.filter { windows.contains($0.id) }
    }

    /// How many windows an agent may keep open in one app. A window per page
    /// or per step fills the user's screen; agents should reuse theirs.
    static let maxWindows = Int(ProcessInfo.processInfo.environment["BACKSEAT_MAX_WINDOWS"] ?? "") ?? 3

    /// Throws if opening another window in `pid` would bother the user: they're
    /// in that app right now (its new window becomes theirs: it takes their
    /// keyboard focus, and in full screen moves them to a Space of its own), or
    /// the agent already has `maxWindows` open there.
    static func checkBudget(pid: pid_t, counting: Bool = true) throws {
        let app = NSRunningApplication(processIdentifier: pid)
        if app?.isActive == true {
            let name = app?.localizedName ?? "this app"
            let mine = shared.open(pid: pid).map { String($0.id) }
            throw ToolError("""
            not opened: the user is in \(name) right now, and a new \(name) window would take their focus \
            (in full screen, it moves them to a Space of its own). \(mine.isEmpty ? "" : "Use a window you already have (\(mine.joined(separator: ", "))). ")\
            Or do this in another app the user isn't in, or wait until they've left \(name).
            """)
        }
        let mine = shared.open(pid: pid)
        guard counting, mine.count + shared.pendingCount(pid, open: mine) >= maxWindows else { return }
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "this app"
        throw ToolError("""
        not opened: you already have \(mine.count) windows open in \(name) (\(mine.map { String($0.id) }.joined(separator: ", "))), \
        and each new one appears on the user's screen. Reuse one of yours, or close_window \
        the ones you're done with first.
        """)
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
        let own = "Work in a window of your own: reuse one you opened, or open one (select_menu_item File > New Window, or launch_app with a url) and use its id. Pass user_window: true only if the user asked you to use their window."
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
