import AppKit

/// Keeps the user's focus where they put it.
///
/// Some apps bring themselves to the front on their own when backseat drives
/// them (Safari and System Settings on launch; Finder, Safari and TextEdit when
/// a command opens a new window). That takes the user's keyboard focus and, if
/// the app lives on another Space, drags the user there.
///
/// FocusGuard listens for app activations as they happen. If an app backseat
/// touched in the last few seconds becomes frontmost, it hands focus straight
/// back to the app the user was using, within milliseconds rather than after a
/// polling interval. Switches the user makes themselves are left alone.
final class FocusGuard: @unchecked Sendable {
    static let shared = FocusGuard()

    private let lock = NSLock()
    /// pid -> until when an activation of it counts as backseat's fault.
    private var touched: [pid_t: Date] = [:]
    /// The app the user last chose to be in.
    private var userApp: NSRunningApplication?
    /// The window the user was in, read while their app was still active: once
    /// another app has taken over, their app can report some other window as
    /// focused (one on the desktop rather than their full-screen one), and
    /// handing focus back to that would leave them on the wrong Space.
    private var userWindow: (pid: pid_t, id: CGWindowID)?
    /// Focus hand-backs not yet reported, by the pid that took focus, so each
    /// tool call reports only what its own app did (agents run in parallel).
    private var notes: [pid_t: [String]] = [:]
    /// Apps being launched by backseat (bundle URL -> until when).
    private var launching: [URL: Date] = [:]

    private init() {
        userApp = NSWorkspace.shared.frontmostApplication
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.activated(app)
        }
    }

    /// Call before acting on an app; activations of it within `seconds` are undone.
    func touch(_ pid: pid_t, seconds: TimeInterval = 4) {
        rememberUserWindow(except: pid)
        lock.lock(); defer { lock.unlock() }
        touched[pid] = max(touched[pid] ?? .distantPast, Date().addingTimeInterval(seconds))
    }

    /// Call before launching an app, whose pid isn't known yet.
    func expectLaunch(of url: URL, seconds: TimeInterval = 10) {
        rememberUserWindow(except: nil)
        lock.lock(); defer { lock.unlock() }
        launching[url.standardizedFileURL] = Date().addingTimeInterval(seconds)
    }

    /// Notes the window the user is in right now, before backseat does
    /// anything that could pull another app forward.
    private func rememberUserWindow(except pid: pid_t?) {
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != pid,
              front.processIdentifier != getpid(),
              let id = AX.attr(AX.app(front.processIdentifier), kAXFocusedWindowAttribute)
                .map({ $0 as! AXUIElement }).flatMap(AX.windowID) else { return }
        lock.lock(); defer { lock.unlock() }
        // Only while the user's app is the one in front, not one we're acting on.
        if (touched[front.processIdentifier] ?? .distantPast) > Date() { return }
        userWindow = (front.processIdentifier, id)
    }

    /// The window to put the user back in, for `app`.
    private func handBackWindow(_ app: NSRunningApplication) -> CGWindowID? {
        lock.lock(); defer { lock.unlock() }
        guard let w = userWindow, w.pid == app.processIdentifier else { return nil }
        return w.id
    }

    /// True if the user just clicked, or just pressed a ⌘ shortcut (⌘-Tab, Spotlight),
    /// on real hardware: they switched apps themselves. Plain typing doesn't
    /// count, and events backseat posts to a process never reach the HID system.
    private var userJustActed: Bool {
        let recent = { (t: CGEventType) in CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: t) < 0.4 }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(where: recent) { return true }
        return recent(.keyDown) && CGEventSource.flagsState(.hidSystemState).contains(.maskCommand)
    }

    /// The app focus is lent to right now (see `borrow`): its activation is ours.
    private var lentTo: pid_t?

    private func activated(_ app: NSRunningApplication) {
        lock.lock()
        if app.processIdentifier == lentTo { lock.unlock(); return }
        let now = Date()
        let launched = app.bundleURL.map { (launching[$0.standardizedFileURL] ?? .distantPast) > now } ?? false
        // An app backseat is launching right now brought itself forward: that's
        // never the user, even if they happened to click somewhere this instant.
        let blamed = launched || ((touched[app.processIdentifier] ?? .distantPast) > now && !userJustActed)
        let user = userApp
        if !blamed { userApp = app }
        lock.unlock()

        guard blamed, let user, user.processIdentifier != app.processIdentifier, !user.isTerminated else { return }
        let window = handBackWindow(user)
        bringToFront(user, window: window)
        holdFocus(for: user, window: window, against: app)
        lock.lock()
        notes[app.processIdentifier, default: []].append("\(app.localizedName ?? "the app") brought itself to the front; focus went straight back to \(user.localizedName ?? "your app")")
        lock.unlock()
    }

    /// An app's activation can land after focus was handed back (Finder's Go to
    /// Folder activates, then the Space switch settles, then the panel opens).
    /// No new activation notification arrives for that, so the user would stay
    /// stuck in the app: check for a moment and hand focus back again.
    private func holdFocus(for user: NSRunningApplication, window: CGWindowID?, against app: NSRunningApplication) {
        let start = Date()
        for delay in [0.1, 0.25, 0.5, 0.8, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !Self.userActed(since: start), !user.isTerminated else { return }
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                // The app took focus again, or the user's app is back in front but
                // they're on the wrong Space (their window isn't on the active one).
                let stranded = front == user.processIdentifier && window.map { !Windows.isOnActiveSpace($0) } == true
                guard front == app.processIdentifier || stranded else { return }
                self.bringToFront(user, window: window)
            }
        }
    }

    /// True if the user clicked, or pressed a ⌘ shortcut, on real hardware since
    /// `date`. Plain typing doesn't count: someone typing into their own app
    /// when another app jumps in front is exactly who needs focus back.
    private static func userActed(since date: Date) -> Bool {
        let elapsed = Date().timeIntervalSince(date)
        let since = { (t: CGEventType) in CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: t) < elapsed }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(where: since) { return true }
        return since(.keyDown) && CGEventSource.flagsState(.hidSystemState).contains(.maskCommand)
    }

    /// Makes `app` frontmost again. NSRunningApplication.activate() is
    /// cooperative since macOS 14 and silently refused for a background
    /// process like backseat, and setting AXFrontmost is ignored too, so use
    /// the WindowServer call window managers use (as if the user clicked it).
    ///
    /// It targets the user's own window, not just the app: with window 0 the
    /// app comes forward but the user stays on whatever Space the other app
    /// dragged them to (a full-screen window's Space, say). Naming the window
    /// switches back to its Space and makes it key again.
    private func bringToFront(_ app: NSRunningApplication, window chosen: CGWindowID? = nil) {
        let pid = app.processIdentifier
        let window = chosen
            ?? AX.attr(AX.app(pid), kAXFocusedWindowAttribute).map { $0 as! AXUIElement }.flatMap(AX.windowID)
            ?? AX.attr(AX.app(pid), kAXMainWindowAttribute).map { $0 as! AXUIElement }.flatMap(AX.windowID)
            ?? 0
        var psn = ProcessSerialNumber()
        if let getPSN = Private.getProcessForPID, let setFront = Private.setFrontProcess,
           getPSN(pid, &psn) == noErr, setFront(&psn, window, Private.kCPSUserGenerated) == 0 {
            if window != 0 { Private.makeKeyWindow(&psn, window) }
            return
        }
        app.activate()
    }

    /// Notes about focus that was handed back since the last call.
    func drainNotes(for pid: pid_t) -> String {
        lock.lock(); defer { lock.unlock() }
        guard let mine = notes.removeValue(forKey: pid), !mine.isEmpty else { return "" }
        return "\n(" + mine.joined(separator: "; ") + ")"
    }

    /// Keeps the user in `window` of `pid`, the app they're using, for a couple
    /// of seconds. A command can put a different window of that app in front
    /// (a new window of the app you're in opens in front of you, and on a Space
    /// of its own if it's full screen): no app activation happens, so `activated`
    /// never sees it. Put the user straight back unless they moved themselves.
    func holdWindow(pid: pid_t, window: CGWindowID) {
        let start = Date()
        for delay in [0.03, 0.08, 0.15, 0.3, 0.5, 0.8, 1.2, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !Self.userActed(since: start),
                      let app = NSRunningApplication(processIdentifier: pid), app.isActive, !app.isTerminated,
                      let now = Ownership.userWindow(pid: pid), now != window,
                      AX.window(id: window, pid: pid) != nil else { return }
                self.bringToFront(app, window: window)
                self.lock.lock()
                self.notes[pid, default: []].append("another \(app.localizedName ?? "app") window came in front of the user's; they were put straight back in their own")
                self.lock.unlock()
            }
        }
    }

    /// The window an app takes the user back to when they next switch to it is
    /// its main window. A command that opens a window (New Window) makes the new
    /// one main, so the user would land in the agent's window instead of theirs.
    /// While the app stays in the background, make `window` main again.
    private var aimed: [pid_t: Date] = [:]

    /// backseat is about to send keys to `pid`'s focused window.
    func aimingKeys(at pid: pid_t) {
        lock.lock(); aimed[pid] = Date(); lock.unlock()
    }

    /// True once keys backseat sent to `pid` have had time to land.
    private func keysSettled(_ pid: pid_t) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(aimed[pid] ?? .distantPast) >= 0.5
    }

    func holdMain(pid: pid_t, window: AXUIElement) {
        guard let id = AX.windowID(window) else { return }
        for delay in [0.05, 0.15, 0.3, 0.6, 1.0, 1.6, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let app = NSRunningApplication(processIdentifier: pid), !app.isActive, !app.isTerminated,
                      AX.window(id: id, pid: pid) != nil else { return }
                let main = AX.attr(AX.app(pid), kAXMainWindowAttribute).map({ $0 as! AXUIElement }).flatMap(AX.windowID)
                let focused = AX.attr(AX.app(pid), kAXFocusedWindowAttribute).map({ $0 as! AXUIElement }).flatMap(AX.windowID)
                // Both: the focused window is the one the user lands in when they
                // switch to the app, and backseat focuses its own to send keys.
                if main != id { AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue) }
                // Not before keys backseat just sent have landed: they go to the
                // focused window when the app gets to them, which would be this one.
                if focused != id, delay >= 0.6, self.keysSettled(pid) { AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue) }
            }
        }
    }

    /// The app's main window, while the user isn't in the app.
    static func mainWindow(ofBackground pid: pid_t) -> AXUIElement? {
        guard NSRunningApplication(processIdentifier: pid)?.isActive == false else { return nil }
        // The focused window is where the user lands on switching to the app.
        // Never one of the agent's own: that would hand them the agent's window.
        let app = AX.app(pid)
        return [kAXFocusedWindowAttribute, kAXMainWindowAttribute]
            .compactMap { AX.attr(app, $0).map { $0 as! AXUIElement } }
            .first { w in AX.windowID(w).map { !Ownership.shared.ownsWindow($0) } ?? false }
    }

    /// Runs an action against `target` with the guard armed for it.
    static func run<T>(target: pid_t, _ body: () async throws -> T) async throws -> (T, String) {
        shared.touch(target)
        // If the user is in this app, remember their window to keep them in it;
        // if not, remember the window the app would take them back to.
        let userWindow = Ownership.userWindow(pid: target)
        let mainBefore = userWindow == nil ? mainWindow(ofBackground: target) : nil
        let result = try await body()
        if let userWindow { shared.holdWindow(pid: target, window: userWindow) }
        if let mainBefore { shared.holdMain(pid: target, window: mainBefore) }
        // Give a self-activation triggered by the action time to arrive and be undone.
        try? await Task.sleep(for: .milliseconds(60))  // activations land within ~25ms
        return (result, shared.drainNotes(for: target))
    }
}

/// Private calls, looked up at runtime so a missing symbol degrades instead of crashing.
enum Private {
    typealias SetFront = @convention(c) (UnsafePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32
    typealias GetPSN = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    static let kCPSUserGenerated: UInt32 = 0x200

    static let setFrontProcess: SetFront? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let sym = dlsym(h, "_SLPSSetFrontProcessWithOptions") else { return nil }
        return unsafeBitCast(sym, to: SetFront.self)
    }()

    typealias PostEventRecord = @convention(c) (UnsafePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> Int32
    static let postEventRecord: PostEventRecord? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let sym = dlsym(h, "SLPSPostEventRecordTo") else { return nil }
        return unsafeBitCast(sym, to: PostEventRecord.self)
    }()

    /// Sends the pair of "make key window" records the WindowServer sends on a
    /// click, so `window` gets keyboard focus, not just its app.
    static func makeKeyWindow(_ psn: UnsafePointer<ProcessSerialNumber>, _ window: CGWindowID) {
        guard let post = postEventRecord else { return }
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: window) { for (i, b) in $0.enumerated() { bytes[0x3c + i] = b } }
        for i in 0x20..<0x30 { bytes[i] = 0xff }
        for kind: UInt8 in [0x01, 0x02] {
            bytes[0x08] = kind
            _ = post(psn, &bytes)
        }
    }

    static let getProcessForPID: GetPSN? = {
        guard let h = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW),
              let sym = dlsym(h, "GetProcessForPID") else { return nil }
        return unsafeBitCast(sym, to: GetPSN.self)
    }()
}

// MARK: Borrowing focus

/// Some commands only exist while their app is active: AppKit sends Bold, Save,
/// New Folder and the like to the key window's first responder, and a background
/// app has no key window, so it disables them. No API runs them otherwise.
///
/// `borrow` makes the app active for a few dozen milliseconds without raising its
/// windows or switching Spaces (kCPSNoWindows), makes the target window key, runs
/// the command, and hands focus back to the user's own window.
extension FocusGuard {
    nonisolated(unsafe) static var _readiness = ""
    var lastReadiness: String { get { Self._readiness } set { Self._readiness = newValue } }
    private func setLent(_ pid: pid_t?) { lock.lock(); lentTo = pid; lock.unlock() }

    func borrow<T>(pid: pid_t, window: CGWindowID?, _ body: () async throws -> T) async throws -> (T, borrowed: Bool) {
        let user = NSWorkspace.shared.frontmostApplication
        // The user is in that app already: nothing to borrow.
        if user?.processIdentifier == pid { return (try await body(), false) }
        guard let getPSN = Private.getProcessForPID, let setFront = Private.setFrontProcess else {
            throw ToolError("can't make the app active on this macOS version")
        }
        var psn = ProcessSerialNumber()
        guard getPSN(pid, &psn) == noErr else { throw ToolError("no process \(pid)") }

        setLent(pid)
        defer {
            if let user, !user.isTerminated { bringToFront(user) }
            setLent(nil)
        }
        let noWindows: UInt32 = 0x400
        guard setFront(&psn, 0, noWindows) == 0 else { throw ToolError("macOS refused to make the app active") }
        let app = AX.app(pid)
        let target = window ?? AX.attr(app, kAXMainWindowAttribute).map { $0 as! AXUIElement }.flatMap(AX.windowID)
            ?? AX.windows(pid).compactMap(AX.windowID).first
        let axTarget = target.flatMap { AX.window(id: $0, pid: pid) }
        // AppKit takes the activation asynchronously, and right after other input
        // it can drop the first "make key" request: keep asking until the window
        // itself says it has focus.
        // Ready once the app itself says it's frontmost (a background window can
        // already call itself "main") and the target window is its focused one.
        for attempt in 0..<80 {
            if attempt % 10 == 0, let target { Private.makeKeyWindow(&psn, target) }
            let frontmost = (AX.attr(app, kAXFrontmostAttribute) as? Bool) == true
            let focused = AX.attr(app, kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
            lastReadiness = "frontmost=\(frontmost) focused=\(focused != nil) isTarget=\(focused.flatMap { f in axTarget.map { CFEqual($0, f) } } ?? false) after \(attempt * 5)ms"
            if frontmost, let focused, axTarget.map({ CFEqual($0, focused) }) ?? true { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        return (try await body(), true)
    }
}
