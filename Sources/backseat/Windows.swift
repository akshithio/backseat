import AppKit
import CoreGraphics

struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let app: String
    let title: String
    /// Global coordinates, top-left origin, in points.
    let frame: CGRect
    let onScreen: Bool
    let layer: Int
    /// 0 (invisible) to 1.
    var alpha: Double = 1

    var line: String {
        let f = frame.integral
        let state = Windows.state(of: self)
        return "window \(id)  pid=\(pid)  \(app)  \"\(title)\"  at (\(Int(f.minX)),\(Int(f.minY))) size \(Int(f.width))x\(Int(f.height))" +
            (state.isEmpty ? "" : "  [\(state.joined(separator: ", "))]")
    }
}

@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSGetActiveSpace") private func CGSGetActiveSpace(_ cid: Int32) -> UInt64
@_silgen_name("CGSCopySpacesForWindows") private func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> Unmanaged<CFArray>?
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> Unmanaged<CFArray>?
@_silgen_name("CGSSpaceGetType") private func CGSSpaceGetType(_ cid: Int32, _ space: UInt64) -> Int32

enum Windows {
    /// Where a window is relative to the user, so an agent knows the layout up
    /// front: every tool works on all of these except screenshot on minimized.
    /// True if window `id` is on some Space. Windows an app keeps ordered out
    /// (helpers, popups not showing) are on none.
    static func hasSpace(_ id: CGWindowID) -> Bool {
        let cid = CGSMainConnectionID()
        return !((CGSCopySpacesForWindows(cid, 7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber]) ?? []).isEmpty
    }

    /// True if window `id` is on the Space the user is looking at.
    static func isOnActiveSpace(_ id: CGWindowID) -> Bool {
        let cid = CGSMainConnectionID()
        let spaces = (CGSCopySpacesForWindows(cid, 7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber])?.map(\.uint64Value) ?? []
        return !Set(spaces).isDisjoint(with: currentSpaces())
    }

    /// The Space each display is showing (one per display when displays have
    /// separate Spaces), not just the one with the menu bar.
    static func currentSpaces() -> Set<UInt64> {
        let cid = CGSMainConnectionID()
        var out: Set<UInt64> = [CGSGetActiveSpace(cid)]
        for d in CGSCopyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] ?? [] {
            if let cur = d["Current Space"] as? [String: Any], let id = (cur["ManagedSpaceID"] as? NSNumber)?.uint64Value { out.insert(id) }
        }
        return out
    }

    static func state(of w: WindowInfo) -> [String] {
        var out: [String] = []
        if Ownership.shared.owns(w.id, pid: w.pid) { out.append("yours: you opened it") }
        let app = NSRunningApplication(processIdentifier: w.pid)
        let axw = AX.window(id: w.id, pid: w.pid)
        if let axw, (AX.attr(axw, kAXMinimizedAttribute) as? Bool) == true { out.append("minimized") }
        if let axw, (AX.attr(axw, "AXFullScreen") as? Bool) == true { out.append("full screen") }
        if app?.isHidden == true { out.append("app hidden") }
        // Panels the app opened on its own (an Open panel at launch, an alert)
        // look like any other window in the list; say what they are.
        if let axw {
            switch AX.string(axw, kAXSubroleAttribute) ?? "" {
            case "AXDialog", "AXSystemDialog": out.append("a dialog window (e.g. an Open panel or alert), not a document: answer or cancel it")
            case "AXFloatingWindow": out.append("a floating panel")
            default: break
            }
        }
        if let axw, AX.elements(axw, kAXChildrenAttribute).contains(where: { AX.string($0, kAXRoleAttribute) == "AXSheet" }) {
            out.append("showing a dialog: deal with it first; the app's Dock icon bounces until it closes")
        }
        if out.contains("minimized") || out.contains("app hidden") { return out }
        let cid = CGSMainConnectionID()
        let spaces = (CGSCopySpacesForWindows(cid, 7, [NSNumber(value: w.id)] as CFArray)?.takeRetainedValue() as? [NSNumber])?.map(\.uint64Value) ?? []
        let active = CGSGetActiveSpace(cid)
        if spaces.contains(active) && w.onScreen {
            out.append(onAnyDisplay(w) ? "on the user's current Space" : "on the user's current Space, but off every display")
        } else if !spaces.isEmpty && !spaces.contains(active) {
            // 4 is a full-screen app's Space.
            out.append(spaces.contains { CGSSpaceGetType(cid, $0) == 4 } ? "on another full-screen Space" : "on another Space")
        } else if !w.onScreen {
            out.append("not on screen")
        }
        if app?.isActive == true, let axw, let focused = AX.attr(AX.app(w.pid), kAXFocusedWindowAttribute),
           CFEqual(focused, axw) {
            out.append("the user's focused window: leave it alone unless asked")
        }
        return out
    }

    /// True if the user could see `w` right now: on their Space, not minimized
    /// or hidden, and not see-through.
    /// How many of the app's menus are open on screen (pop-up menu level).
    static func openMenuCount(pid: pid_t) -> Int {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return list.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) && ($0[kCGWindowLayer as String] as? Int) == menuLevel }.count
    }

    /// True if any part of `w` is on a connected display.
    static func onAnyDisplay(_ w: WindowInfo) -> Bool {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).contains { CGDisplayBounds($0).intersects(w.frame) }
    }

    static func visibleToUser(_ w: WindowInfo) -> Bool {
        guard w.onScreen, w.alpha >= 0.1, onAnyDisplay(w), NSRunningApplication(processIdentifier: w.pid)?.isHidden != true else { return false }
        let cid = CGSMainConnectionID()
        let spaces = (CGSCopySpacesForWindows(cid, 7, [NSNumber(value: w.id)] as CFArray)?.takeRetainedValue() as? [NSNumber])?.map(\.uint64Value) ?? []
        return spaces.isEmpty || spaces.contains(CGSGetActiveSpace(cid))  // onScreen already checked
    }

    static func all(includeOffscreen: Bool = false) -> [WindowInfo] {
        let options: CGWindowListOption = includeOffscreen
            ? [.excludeDesktopElements]
            : [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        // Normal (0), floating (3: palettes, inspectors) and modal-panel (8) levels;
        // above that are the menu bar, Dock and status items.
        let appLevels = [0, Int(CGWindowLevelForKey(.floatingWindow)), Int(CGWindowLevelForKey(.modalPanelWindow))]
        return list.compactMap(parse).filter { appLevels.contains($0.layer) && $0.frame.width > 1 && $0.frame.height > 1 }
    }

    /// An app's real windows, as the app itself reports them through
    /// accessibility (including ones on other Spaces). Excludes the helper
    /// strips, sheets and just-closed windows CoreGraphics also lists; sheets
    /// show up inside their parent window's UI tree instead.
    static func list(pid: pid_t) -> [WindowInfo] {
        let cg = Dictionary(all(includeOffscreen: true).filter { $0.pid == pid }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var axWindows = AX.windows(pid)
        // A real window the quick lookup missed (one that moved to another
        // Space after it stopped being focused): look for it specifically.
        let found = Set(axWindows.compactMap(AX.windowID))
        for c in cg.values where !found.contains(c.id) && c.layer == 0 && c.frame.width >= 100 && c.frame.height >= 100 {
            if let w = AX.window(id: c.id, pid: pid, search: true) { axWindows.append(w) }
        }
        return axWindows.compactMap { axw in
            guard let id = AX.windowID(axw), let c = cg[id] else { return nil }
            return WindowInfo(id: id, pid: pid, app: c.app, title: AX.string(axw, kAXTitleAttribute) ?? c.title,
                              frame: AX.frame(axw) ?? c.frame, onScreen: c.onScreen, layer: c.layer, alpha: c.alpha)
        }
    }

    /// The window's frame as accessibility reports it: the space every
    /// window-relative coordinate is measured in. Falls back to CoreGraphics.
    static func frame(of window: WindowInfo) -> CGRect {
        AX.window(id: window.id, pid: window.pid).flatMap(AX.frame) ?? window.frame
    }

    /// Fills in titles CoreGraphics left blank, using the app's AX windows.
    static func withAXTitles(_ windows: [WindowInfo]) -> [WindowInfo] {
        var byPid: [pid_t: [CGWindowID: String]] = [:]
        return windows.map { w in
            guard w.title.isEmpty else { return w }
            if byPid[w.pid] == nil {
                var titles: [CGWindowID: String] = [:]
                for axw in AX.windows(w.pid) {
                    if let id = AX.windowID(axw) { titles[id] = AX.string(axw, kAXTitleAttribute) ?? "" }
                }
                byPid[w.pid] = titles
            }
            let title = byPid[w.pid]?[w.id] ?? ""
            return WindowInfo(id: w.id, pid: w.pid, app: w.app, title: title, frame: w.frame, onScreen: w.onScreen, layer: w.layer, alpha: w.alpha)
        }
    }

    static func get(_ id: CGWindowID) throws -> WindowInfo {
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]] ?? []
        guard let info = list.first.flatMap(parse) else {
            throw ToolError("no window with id \(id); call list_windows for current ids")
        }
        return info
    }

    private static func parse(_ w: [String: Any]) -> WindowInfo? {
        guard let id = w[kCGWindowNumber as String] as? Int,
              let pid = w[kCGWindowOwnerPID as String] as? Int,
              let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: boundsDict)
        else { return nil }
        let title = w[kCGWindowName as String] as? String ?? ""
        return WindowInfo(
            id: CGWindowID(id),
            pid: pid_t(pid),
            app: w[kCGWindowOwnerName as String] as? String ?? "?",
            title: title,
            frame: frame,
            onScreen: w[kCGWindowIsOnscreen as String] as? Bool ?? false,
            layer: w[kCGWindowLayer as String] as? Int ?? 0,
            alpha: w[kCGWindowAlpha as String] as? Double ?? 1
        )
    }
}
