import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

/// Hands out short ids ("e12") for AX elements so the agent can refer back to
/// them. The same element keeps the same id across calls.
final class ElementStore: @unchecked Sendable {
    static let shared = ElementStore()
    private let lock = NSLock()
    private var elements: [String: AXUIElement] = [:]
    private var byHash: [CFHashCode: [(String, AXUIElement)]] = [:]
    private var next = 1

    func add(_ element: AXUIElement) -> String {
        lock.lock(); defer { lock.unlock() }
        let hash = CFHash(element)
        if let existing = byHash[hash]?.first(where: { CFEqual($0.1, element) }) { return existing.0 }
        if elements.count > 50_000 { elements.removeAll(); byHash.removeAll() }
        let id = "e\(next)"
        next += 1
        elements[id] = element
        byHash[hash, default: []].append((id, element))
        return id
    }

    /// The element for an id, without outlining its window.
    func lookup(_ id: String) -> AXUIElement? {
        lock.lock(); defer { lock.unlock() }
        return elements[id]
    }

    func get(_ id: String) throws -> AXUIElement {
        lock.lock(); defer { lock.unlock() }
        guard let e = elements[id] else {
            throw ToolError("unknown element '\(id)'; element ids come from get_ui_tree or find_elements")
        }
        // The UI it pointed at may be gone (the window navigated or closed).
        var role: AnyObject?
        if AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &role) == .invalidUIElement {
            throw ToolError("element '\(id)' no longer exists (its UI changed or closed); get fresh ids with get_ui_tree or find_elements")
        }
        Overlay.shared.highlight(element: e)
        return e
    }
}

enum AX {
    static func app(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 3)
        return app
    }

    static func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
    }

    /// Several attributes in one round trip to the app. Each separate read is
    /// its own call into the app, which adds up to seconds on a big web page.
    /// Attributes the element doesn't have come back nil.
    static func values(_ e: AXUIElement, _ names: [String]) -> [AnyObject?] {
        var out: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(e, names as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &out) == .success,
              let all = out as? [AnyObject], all.count == names.count else { return names.map { _ in nil } }
        return all.map { v in
            CFGetTypeID(v) == AXValueGetTypeID() && AXValueGetType(v as! AXValue) == .axError ? nil : v
        }
    }

    static func string(_ e: AXUIElement, _ name: String) -> String? {
        (attr(e, name) as? String)?.withoutDirectionMarks
    }

    static func elements(_ e: AXUIElement, _ name: String) -> [AXUIElement] {
        attr(e, name) as? [AXUIElement] ?? []
    }

    static func pid(_ e: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(e, &pid)
        return pid
    }

    static func windowID(_ e: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(e, &id) == .success && id != 0 ? id : nil
    }

    /// `search`: when a tool asks for this one window, keep looking for it
    /// longer if the quick lookup misses (never while listing many windows).
    static func window(id: CGWindowID, pid: pid_t, search: Bool = false) -> AXUIElement? {
        if let w = windows(pid).first(where: { windowID($0) == id }) { return w }
        guard search, Windows.all(includeOffscreen: true).contains(where: { $0.id == id && $0.pid == pid }) else { return nil }
        let w = windowsOnOtherSpaces(pid, budget: 3, upTo: 200_000, stopAt: id).first { windowID($0) == id }
        if let w { remember([w], pid: pid) }
        return w
    }

    /// Window elements seen before, by pid. A window on another Space drops out
    /// of the app's window list; one seen earlier (while it was focused, right
    /// after it opened) stays reachable through the element already in hand.
    nonisolated(unsafe) private static var seenWindows: [pid_t: [CGWindowID: AXUIElement]] = [:]
    private static let seenLock = NSLock()

    private static func remember(_ windows: [AXUIElement], pid: pid_t) {
        seenLock.lock(); defer { seenLock.unlock() }
        for w in windows { if let id = windowID(w) { seenWindows[pid, default: [:]][id] = w } }
    }

    private static func remembered(_ pid: pid_t) -> [CGWindowID: AXUIElement] {
        seenLock.lock(); defer { seenLock.unlock() }
        return seenWindows[pid] ?? [:]
    }

    /// All of an app's windows, including ones on other Spaces.
    static func windows(_ pid: pid_t) -> [AXUIElement] {
        var result = elements(app(pid), kAXWindowsAttribute)
        defer { remember(result, pid: pid) }
        var seen = Set(result.compactMap(windowID))
        let cgIDs = Set(Windows.all(includeOffscreen: true).filter { $0.pid == pid }.map(\.id))
        if cgIDs.isSubset(of: seen) { return result }
        for (id, w) in remembered(pid) where cgIDs.contains(id) && !seen.contains(id) {
            var role: AnyObject?
            guard AXUIElementCopyAttributeValue(w, kAXRoleAttribute as CFString, &role) == .success else { continue }
            result.append(w)
            seen.insert(id)
        }
        if cgIDs.isSubset(of: seen) { return result }
        // kAXWindowsAttribute only covers the current Space. The focused and
        // main windows are still reachable from elsewhere, and touching them
        // makes the app allocate ids the remote-token scan can find.
        let app = app(pid)
        var others: [AXUIElement] = []
        for key in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let w = attr(app, key) { others.append(w as! AXUIElement) }
        }
        if let focused = attr(app, kAXFocusedUIElementAttribute), let w = attr(focused as! AXUIElement, kAXWindowAttribute) {
            others.append(w as! AXUIElement)
        }
        for w in others + windowsOnOtherSpaces(pid) {
            if let id = windowID(w), seen.insert(id).inserted { result.append(w) }
        }
        return result
    }

    /// Windows on other Spaces that the app has already vended elements for
    /// are reachable by constructing their remote tokens directly, the same
    /// trick AltTab uses: pid, 0, 'coco', element id.
    nonisolated(unsafe) private static var recentScans: [pid_t: (at: Date, windows: [AXUIElement])] = [:]
    private static let scanLock = NSLock()

    /// Apps with big accessibility trees (browsers) hand out element ids far
    /// past the default range; a search for one known window goes further.
    private static func windowsOnOtherSpaces(_ pid: pid_t, budget: TimeInterval = 0.5, upTo limit: UInt64 = 2000,
                                             stopAt wanted: CGWindowID? = nil) -> [AXUIElement] {
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: pid, toByteOffset: 0, as: pid_t.self)
            buf.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
            buf.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self)
        }
        // Listing windows asks once per window; reuse a scan from a moment ago.
        if wanted == nil {
            scanLock.lock()
            let recent = recentScans[pid]
            scanLock.unlock()
            if let recent, Date().timeIntervalSince(recent.at) < 2 { return recent.windows }
        }
        var found: [AXUIElement] = []
        defer {
            if wanted == nil { scanLock.lock(); recentScans[pid] = (Date(), found); scanLock.unlock() }
        }
        let deadline = Date().addingTimeInterval(budget)
        for elementID: UInt64 in 0..<limit {
            token.withUnsafeMutableBytes { $0.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self) }
            guard let e = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else { continue }
            if string(e, kAXRoleAttribute) == kAXWindowRole {
                found.append(e)
                if let wanted, windowID(e) == wanted { break }
            }
            if Date() > deadline { break }
        }
        return found
    }

    /// The deepest element of a window containing a window-relative point.
    /// Walks the tree itself: AXUIElementCopyElementAtPosition answers with
    /// whatever is on screen there, which for a covered window is another app's UI.
    static func element(at local: CGPoint, in window: WindowInfo) -> AXUIElement? {
        guard let root = self.window(id: window.id, pid: window.pid), let origin = frame(root)?.origin else { return nil }
        let point = CGPoint(x: origin.x + local.x, y: origin.y + local.y)
        var best: AXUIElement?
        var visited = 0
        func visit(_ e: AXUIElement, depth: Int) {
            visited += 1
            guard depth < 60, visited < 5000 else { return }
            if let f = frame(e), f.width > 0, f.height > 0 {
                guard f.contains(point) else { return }
                best = e
            }
            for child in elements(e, kAXChildrenAttribute) { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)
        return best
    }

    /// Throws instead of acting when the app would reject the input with the
    /// alert sound: the element is disabled, or its window has a sheet open
    /// and the element isn't inside that sheet.
    static func checkReachable(_ e: AXUIElement, what: String) throws {
        if (attr(e, kAXEnabledAttribute) as? Bool) == false {
            throw ToolError("\(what) is disabled; not clicked (the app would just beep)")
        }
        guard let window = containingWindow(e) else { return }
        let sheets = elements(window, kAXChildrenAttribute).filter { string($0, kAXRoleAttribute) == "AXSheet" }
        guard !sheets.isEmpty else { return }
        var cur: AXUIElement? = e
        for _ in 0..<80 {
            guard let c = cur else { break }
            if string(c, kAXRoleAttribute) == "AXSheet" { return }
            cur = attr(c, kAXParentAttribute).map { $0 as! AXUIElement }
        }
        let title = sheets.first.flatMap { string($0, kAXTitleAttribute) ?? string($0, kAXDescriptionAttribute) } ?? ""
        throw ToolError("the window has a sheet open\(title.isEmpty ? "" : " (\"\(title)\")"); \(what) is behind it, so the app would just beep. Act on the sheet first (get_ui_tree on the window shows it).")
    }

    /// How an agent acts on `e`: press it, or select it (list and table rows
    /// select through AXSelected and have no press action). Nil if neither.
    static func howToAct(_ e: AXUIElement) -> String? {
        let acts = actions(e)
        if acts.contains(kAXPressAction) || acts.contains(kAXPickAction) { return "press" }
        if ["AXRow", "AXCell", "AXOutlineRow"].contains(string(e, kAXRoleAttribute) ?? ""), isSettable(e, kAXSelectedAttribute) {
            return "select"
        }
        return nil
    }

    /// `e` or its nearest ancestor that can be acted on, within a few levels:
    /// labels in a list row or a button are usually bare static text.
    static func actionable(_ e: AXUIElement) -> (element: AXUIElement, how: String)? {
        var cur: AXUIElement? = e
        for _ in 0..<6 {
            guard let c = cur else { return nil }
            let role = string(c, kAXRoleAttribute) ?? ""
            if role == kAXWindowRole || role == "AXWebArea" { return nil }
            if let how = howToAct(c) { return (c, how) }
            cur = attr(c, kAXParentAttribute).map { $0 as! AXUIElement }
        }
        return nil
    }

    /// Menus of `pid` that are open right now (a context or pop-up menu), found
    /// under the app, `near` and its ancestors. Menu-bar menus aren't included.
    static func openMenus(pid: pid_t, near: AXUIElement? = nil) -> [AXUIElement] {
        var found: [AXUIElement] = []
        func add(_ m: AXUIElement) {
            guard string(m, kAXRoleAttribute) == "AXMenu", !found.contains(where: { CFEqual($0, m) }),
                  !elements(m, kAXChildrenAttribute).isEmpty, frame(m).map({ $0.width > 0 && $0.height > 0 }) ?? false else { return }
            found.append(m)
        }
        for c in elements(app(pid), kAXChildrenAttribute) { add(c) }
        var cur = near
        for _ in 0..<4 {
            guard let c = cur else { break }
            for child in elements(c, kAXChildrenAttribute) { add(child) }
            cur = attr(c, kAXParentAttribute).map { $0 as! AXUIElement }
        }
        return found
    }

    /// A cheap fingerprint of what a window shows (roles, labels, values of
    /// its first few hundred elements), to tell whether an action changed it.
    static func digest(_ window: AXUIElement, limit: Int = 400) -> Int {
        var hasher = Hasher()
        var seen = 0
        func visit(_ e: AXUIElement, depth: Int) {
            seen += 1
            guard seen < limit, depth < 30 else { return }
            let role = string(e, kAXRoleAttribute) ?? ""
            if role == "AXMenuBar" || role == "AXMenu" { return }
            hasher.combine(role)
            hasher.combine(string(e, kAXTitleAttribute))
            hasher.combine(valueString(e))
            for c in elements(e, kAXChildrenAttribute) { visit(c, depth: depth + 1) }
        }
        visit(window, depth: 0)
        return hasher.finalize()
    }

    /// The window element containing an element (or the element itself, if it is a window).
    static func containingWindow(_ e: AXUIElement) -> AXUIElement? {
        if string(e, kAXRoleAttribute) == kAXWindowRole { return e }
        return attr(e, kAXWindowAttribute).map { $0 as! AXUIElement }
    }

    /// Global top-left-origin frame, in points.
    static func frame(_ e: AXUIElement) -> CGRect? {
        guard let p = attr(e, kAXPositionAttribute), let s = attr(e, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    static func actions(_ e: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(e, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    /// Custom actions arrive as "Name:Copy\nTarget:…\nSelector:…"; show just the name.
    static func displayName(ofAction raw: String) -> String {
        if raw.hasPrefix("Name:") {
            return String(raw.dropFirst(5).prefix { $0 != "\n" })
        }
        return raw.hasPrefix("AX") ? String(raw.dropFirst(2)) : raw
    }

    /// Finds the raw action name matching what the agent asked for ("press", "AXPress", "Copy").
    static func resolveAction(_ requested: String, on e: AXUIElement) -> String {
        let want = requested.lowercased().replacingOccurrences(of: "ax", with: "", options: .anchored)
        return actions(e).first { displayName(ofAction: $0).lowercased() == want }
            ?? (requested.hasPrefix("AX") ? requested : "AX" + requested.prefix(1).uppercased() + requested.dropFirst())
    }

    static func isSettable(_ e: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(e, name as CFString, &settable) == .success && settable.boolValue
    }

    static func valueString(_ e: AXUIElement) -> String? {
        switch attr(e, kAXValueAttribute) {
        case let s as String: return s.withoutDirectionMarks
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    /// Presses `e`. A press that quits the app or closes the element's window
    /// (Delete in a "keep this document?" dialog, Quit, Close) gets no reply,
    /// which AX reports as an error; that's success, so say what happened instead.
    @discardableResult
    static func press(_ e: AXUIElement, _ what: String) throws -> String {
        let err = AXUIElementPerformAction(e, kAXPressAction as CFString)
        guard err == .cannotComplete || err == .invalidUIElement else {
            try check(err, what)
            return ""
        }
        let pid = pid(e)
        for _ in 0..<10 {
            if NSRunningApplication(processIdentifier: pid)?.isTerminated ?? true { return " (the app quit)" }
            var role: AnyObject?
            if AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &role) == .invalidUIElement { return " (it closed)" }
            usleep(100_000)
        }
        try check(err, what)
        return ""
    }

    static func check(_ err: AXError, _ what: String) throws {
        guard err == .success else { throw ToolError("\(what) failed: \(describe(err))") }
    }

    static func describe(_ err: AXError) -> String {
        switch err {
        case .apiDisabled: return "Accessibility permission not granted"
        case .actionUnsupported: return "action not supported by this element"
        case .attributeUnsupported: return "attribute not supported by this element"
        case .cannotComplete: return "app did not respond"
        case .invalidUIElement: return "element no longer exists; refresh with get_ui_tree"
        case .illegalArgument: return "illegal argument"
        case .notImplemented: return "not implemented by the app"
        default: return "AXError \(err.rawValue)"
        }
    }
}

/// One rendered node of a UI tree.
struct Node {
    let id: String
    let depth: Int
    let role: String
    let label: String
    let value: String?
    let frame: CGRect?
    let actions: [String]
    let enabled: Bool
    let focused: Bool
    let settable: Bool
    var note: String? = nil

    func line(relativeTo origin: CGPoint) -> String {
        if let note { return String(repeating: "  ", count: depth) + note }
        var s = String(repeating: "  ", count: depth) + "\(id) \(role)"
        if !label.isEmpty { s += " \"\(label.clipped(80))\"" }
        if let value, !value.isEmpty { s += " value=\"\(value.clipped(80))\"" }
        if let f = frame {
            s += " @(\(Int(f.minX - origin.x)),\(Int(f.minY - origin.y)) \(Int(f.width))x\(Int(f.height)))"
        }
        let acts = actions.filter { $0 != "AXShowMenu" && $0 != "AXScrollToVisible" }
            .map(AX.displayName(ofAction:))
        if !acts.isEmpty { s += " [" + acts.joined(separator: ",") + "]" }
        if settable { s += " editable" }
        if focused { s += " focused" }
        if !enabled { s += " disabled" }
        return s
    }
}

enum Tree {
    /// Roles that add nesting but rarely carry meaning on their own.
    private static let passthrough: Set<String> = ["AXGroup", "AXSplitGroup", "AXLayoutArea", "AXLayoutItem", "AXUnknown"]
    /// Containers whose rows are collapsed after `rowLimit` unless they are the root.
    private static let lists: Set<String> = ["AXOutline", "AXTable", "AXList", "AXBrowser"]
    static let rowLimit = 25

    static func walk(_ root: AXUIElement, maxDepth: Int, maxNodes: Int, includeMenus: Bool = false,
                     collapseLists: Bool = true, rowLimit: Int = Tree.rowLimit) -> (nodes: [Node], truncated: Bool) {
        var nodes: [Node] = []
        var truncated = false
        let focusedElement = AX.attr(AX.app(AX.pid(root)), kAXFocusedUIElementAttribute).map { $0 as! AXUIElement }

        func visit(_ e: AXUIElement, depth: Int, renderDepth: Int) {
            if nodes.count >= maxNodes { truncated = true; return }
            let role = AX.string(e, kAXRoleAttribute) ?? "?"
            if !includeMenus && (role == "AXMenuBar" || role == "AXMenu") { return }
            let label = label(e)
            let value = AX.valueString(e)
            var children = AX.elements(e, kAXChildrenAttribute)
            let actions = AX.actions(e)
            let boring = passthrough.contains(role) && label.isEmpty && (value ?? "").isEmpty
                && actions.allSatisfy { $0 == "AXShowMenu" || $0 == "AXScrollToVisible" }

            var nextRender = renderDepth
            var id = ""
            if !boring || depth == 0 {
                id = ElementStore.shared.add(e)
                nodes.append(Node(
                    id: id,
                    depth: renderDepth,
                    role: role,
                    label: label,
                    value: value,
                    frame: AX.frame(e),
                    actions: actions,
                    enabled: (AX.attr(e, kAXEnabledAttribute) as? Bool) ?? true,
                    focused: focusedElement.map { CFEqual($0, e) } ?? false,
                    settable: AX.isSettable(e, kAXValueAttribute) && role != "AXScrollBar" && role != "AXSplitter"
                ))
                nextRender += 1
            }
            guard depth < maxDepth else {
                if !children.isEmpty { truncated = true }
                return
            }
            var hidden = 0
            var totalRows = 0
            if collapseLists, depth > 0, lists.contains(role) {
                let rows = AX.elements(e, kAXRowsAttribute)
                totalRows = rows.count
                if rows.count > rowLimit {
                    hidden = rows.count - rowLimit
                    let shown = rows.prefix(rowLimit)
                    children = children.filter { c in !rows.contains { CFEqual($0, c) } || shown.contains { CFEqual($0, c) } }
                }
            }
            for child in children { visit(child, depth: depth + 1, renderDepth: nextRender) }
            if hidden > 0 {
                nodes.append(Node(id: "", depth: nextRender, role: "", label: "", value: nil, frame: nil, actions: [],
                                  enabled: true, focused: false, settable: false,
                                  note: "… \(hidden) more rows (get_ui_tree element_id=\(id) max_rows=\(totalRows) shows all)"))
            }
        }

        visit(root, depth: 0, renderDepth: 0)
        return (nodes, truncated)
    }

    /// Elements whose role matches and whose label or value contains `text`,
    /// nearest the top first. Reads each element's attributes in one round
    /// trip, and stops at `limit` matches or when `budget` runs out, so a
    /// search on a huge web page answers in a few seconds at most.
    static func search(_ root: AXUIElement, text: String?, role: String?, limit: Int,
                       budget: TimeInterval = 4) -> (matches: [AXUIElement], visited: Int, complete: Bool) {
        let keys = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, "AXLabel",
                    kAXPlaceholderValueAttribute, kAXValueAttribute, kAXChildrenAttribute]
        let deadline = Date().addingTimeInterval(budget)
        var queue = [root]
        var head = 0
        var matches: [AXUIElement] = []
        while head < queue.count {
            if matches.count >= limit || Date() > deadline || head >= 20_000 { return (matches, head, false) }
            let e = queue[head]
            head += 1
            let v = AX.values(e, keys)
            let r = (v[0] as? String) ?? ""
            if r == "AXMenuBar" || r == "AXMenu" { continue }
            if role.map({ r.lowercased() == $0.lowercased() }) ?? true {
                if let text {
                    var label = [v[1], v[2], v[3], v[4]].compactMap { ($0 as? String)?.withoutDirectionMarks }.first { !$0.isEmpty } ?? ""
                    // Web headings and links keep their text in a child.
                    if label.isEmpty, r == "AXHeading" || r == "AXLink" { label = Tree.label(e) }
                    let value = (v[5] as? String)?.withoutDirectionMarks ?? (v[5] as? NSNumber)?.stringValue ?? ""
                    if label.lowercased().contains(text) || value.lowercased().contains(text) { matches.append(e) }
                } else {
                    matches.append(e)
                }
            }
            if let kids = v[6] as? [AXUIElement] { queue += kids }
        }
        return (matches, head, true)
    }

    /// One element as a tree line, for search results.
    static func line(_ e: AXUIElement, relativeTo origin: CGPoint) -> String {
        let role = AX.string(e, kAXRoleAttribute) ?? "?"
        return Node(id: ElementStore.shared.add(e), depth: 0, role: role, label: label(e), value: AX.valueString(e),
                    frame: AX.frame(e), actions: AX.actions(e), enabled: (AX.attr(e, kAXEnabledAttribute) as? Bool) ?? true,
                    focused: false, settable: AX.isSettable(e, kAXValueAttribute) && role != "AXScrollBar" && role != "AXSplitter")
            .line(relativeTo: origin)
    }

    static func label(_ e: AXUIElement) -> String {
        for key in [kAXTitleAttribute, kAXDescriptionAttribute, "AXLabel", kAXPlaceholderValueAttribute, kAXHelpAttribute] {
            if let s = AX.string(e, key), !s.isEmpty { return s }
        }
        // Identifiers are for developers ("generalSection",
        // "com.apple.systempreferences.GeneralSettings"); only words help.
        if let s = AX.string(e, kAXIdentifierAttribute), s.contains(" ") { return s }
        if let titleElement = AX.attr(e, kAXTitleUIElementAttribute), CFGetTypeID(titleElement) == AXUIElementGetTypeID(),
           let s = AX.string(titleElement as! AXUIElement, kAXValueAttribute) {
            return s
        }
        let role = AX.string(e, kAXRoleAttribute) ?? ""
        // Web headings and links keep their text in a child.
        if role == "AXHeading" || role == "AXLink" {
            let text = AX.elements(e, kAXChildrenAttribute).compactMap { AX.valueString($0) ?? AX.string($0, kAXTitleAttribute) }
                .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        // Window buttons (close, minimize, zoom) only describe themselves through their subrole.
        if let sub = AX.string(e, kAXSubroleAttribute), sub.hasSuffix("Button"), sub != "AXButton",
           let desc = AX.string(e, kAXRoleDescriptionAttribute) {
            return desc
        }
        return ""
    }
}

extension String {
    /// Apps like Calculator wrap text in invisible bidi marks (U+200E etc.).
    var withoutDirectionMarks: String {
        unicodeScalars.contains { (0x200E...0x200F).contains($0.value) || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value) }
            ? String(String.UnicodeScalarView(unicodeScalars.filter { !((0x200E...0x200F).contains($0.value) || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value)) }))
            : self
    }

    /// Like truncated, but says how much was cut so a caller knows the value
    /// isn't what it sees (element_info or read_text show it whole).
    func clipped(_ n: Int) -> String {
        let flat = replacingOccurrences(of: "\n", with: "⏎")
        return flat.count <= n ? flat : String(flat.prefix(n - 1)) + "…(+\(flat.count - n + 1) chars)"
    }

    func truncated(_ n: Int) -> String {
        let flat = replacingOccurrences(of: "\n", with: "⏎")
        return flat.count <= n ? flat : String(flat.prefix(n - 1)) + "…"
    }
}
