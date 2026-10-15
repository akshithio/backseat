import AppKit
import ApplicationServices
import MCP

enum Output {
    case text(String)
    case image(Data, mime: String, caption: String)

    var content: [Tool.Content] {
        switch self {
        case .text(let s):
            return [.text(text: s, annotations: nil, _meta: nil)]
        case .image(let data, let mime, let caption):
            return [
                .image(data: data.base64EncodedString(), mimeType: mime, annotations: nil, _meta: nil),
                .text(text: caption, annotations: nil, _meta: nil),
            ]
        }
    }
}

private func schema(_ properties: [String: Value], required: [String] = []) -> Value {
    var s: [String: Value] = ["type": "object", "properties": .object(properties)]
    if !required.isEmpty { s["required"] = .array(required.map { .string($0) }) }
    return .object(s)
}

private func prop(_ type: String, _ description: String) -> Value {
    .object(["type": .string(type), "description": .string(description)])
}

private let windowID = prop("integer", "Window id from list_windows.")
private let elementID = prop("string", "Element id (e.g. \"e12\") from get_ui_tree or find_elements.")
private let pidProp = prop("integer", "Process id from list_apps or list_windows.")
private let userWindow = prop("boolean", "Act in (or read) one of the user's own windows or the window they're working in. Only when the user asked for that window; otherwise work in a window you opened. Default false.")

enum Tools {
    static let all: [Tool] = [
        Tool(
            name: "permissions",
            description: "Report whether backseat has the Accessibility and Screen Recording permissions it needs.",
            inputSchema: schema([:]),
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "list_apps",
            description: "List running apps with a UI: pid, name, bundle id, and whether each is the user's frontmost app.",
            inputSchema: schema([:]),
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "list_windows",
            description: "List windows (id, pid, app, title, global frame in points). With pid, lists that app's real windows, including ones off screen or on other Spaces (sheets and dialogs appear inside their window's UI tree). Window ids are what screenshot, get_ui_tree and click take; Each window says where it is: on the user's current Space or another (full-screen) Space, minimized, app hidden, showing a dialog, or the user's focused window. Every tool works on all of them, except screenshot on minimized windows.",
            inputSchema: schema([
                "pid": prop("integer", "Only windows owned by this process."),
                "include_offscreen": prop("boolean", "Include minimized or hidden windows. Default false."),
            ]),
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "launch_app",
            description: "Launch or reveal an app in the background without taking focus from the user, optionally opening a URL or file in it (a web page, a document). Returns its pid and windows.",
            inputSchema: schema([
                "bundle_id": prop("string", "e.g. com.apple.TextEdit"),
                "name": prop("string", "App name, e.g. TextEdit. Used if bundle_id is absent."),
                "path": prop("string", "Path to an .app bundle or executable."),
                "arguments": .object(["type": "array", "items": .object(["type": "string"]), "description": "Command-line arguments."]),
                "url": prop("string", "A URL or file path to open, in the given app or else the default one (https://… opens in the default browser)."),
            ])
        ),
        Tool(
            name: "get_ui_tree",
            description: """
            Read a window's accessibility tree. Each line is: id role "label" value="…" @(x,y wxh) [actions] flags. \
            Coordinates are window-relative points, the same space screenshot (scale 1) and click use. \
            Prefer acting on element ids over coordinates: it is faster, exact, and works in covered windows.
            """,
            inputSchema: schema([
                "user_window": userWindow,
                "window_id": windowID,
                "pid": prop("integer", "Use this app's main window when window_id is not given."),
                "element_id": prop("string", "Only the subtree under this element."),
                "max_depth": prop("integer", "Default 40."),
                "max_nodes": prop("integer", "Default 400."),
                "max_rows": prop("integer", "Rows shown per list or table before the rest are summarized. Default 25."),
            ]),
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "find_elements",
            description: "Search a window's accessibility tree for elements whose label or value contains `text` and/or whose role matches `role`.",
            inputSchema: schema([
                "user_window": userWindow,
                "window_id": windowID,
                "pid": prop("integer", "Use this app's main window when window_id is not given."),
                "text": prop("string", "Case-insensitive substring of label or value."),
                "role": prop("string", "e.g. AXButton, AXTextField, button, textfield."),
                "limit": prop("integer", "Default 30."),
            ]),
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "element_info",
            description: "All accessibility attributes and actions of one element.",
            inputSchema: schema([
                "user_window": userWindow,"element_id": elementID], required: ["element_id"]),
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "perform_action",
            description: "Perform an accessibility action on an element without moving the cursor: press, increment, decrement, confirm, cancel, pick, raise, showMenu.",
            inputSchema: schema([
                "user_window": userWindow,
                "element_id": elementID,
                "action": prop("string", "Default press."),
                "force": prop("boolean", "Allow showMenu, which pops a menu up on the user's screen."),
            ], required: ["element_id"])
        ),
        Tool(
            name: "set_value",
            description: "Set an element's value directly (text fields, sliders, checkboxes, steppers). Can also set another attribute, e.g. AXFocused or AXSelected.",
            inputSchema: schema([
                "user_window": userWindow,
                "element_id": elementID,
                "value": prop("string", "New value. Numbers and true/false are converted when the attribute needs them; ranges (e.g. AXSelectedTextRange) take \"location,length\"."),
                "attribute": prop("string", "Default AXValue."),
            ], required: ["element_id", "value"])
        ),
        Tool(
            name: "type_text",
            description: """
            Type text into an app in the background. With method "ax" (default when possible) text is inserted at the \
            caret of the element (or the app's focused element) through accessibility. With method "keys" it sends \
            key events to the app's process only. Neither touches the user's keyboard focus.
            """,
            inputSchema: schema([
                "user_window": userWindow,
                "text": prop("string", "Text to type. In keys mode \\n presses Return."),
                "element_id": prop("string", "Element to type into; it becomes the app's focused element."),
                "pid": prop("integer", "Type into this app's focused element."),
                "method": prop("string", "auto (default), ax, or keys."),
            ], required: ["text"])
        ),
        Tool(
            name: "press_key",
            description: "Send a key or shortcut (e.g. return, escape, cmd+s, shift+tab) to one app's process only.",
            inputSchema: schema([
                "user_window": userWindow,
                "key": prop("string", "Key name with optional modifiers joined by +."),
                "pid": pidProp,
                "window_id": prop("integer", "Alternative to pid."),
                "element_id": prop("string", "Focus this element in its app first."),
                "repeat": prop("integer", "Default 1."),
            ], required: ["key"])
        ),
        Tool(
            name: "click",
            description: """
            Click an element or a point in a window without moving the user's cursor, taking their focus, or \
            activating the app (so the user is never pulled to another Space). A plain click on something \
            pressable uses accessibility; anything else (canvas, custom views, right/double clicks) is sent as \
            pointer events to that window only. Works on covered, background and off-screen windows. x/y are \
            window-relative points, the same space as screenshot at scale 1.
            """,
            inputSchema: schema([
                "user_window": userWindow,
                "element_id": elementID,
                "element_ids": .object(["type": "array", "items": .object(["type": "string"]), "description": "Press several elements in order (e.g. calculator keys), in one call."]),
                "window_id": windowID,
                "x": prop("number", "Window-relative x in points."),
                "y": prop("number", "Window-relative y in points."),
                "button": prop("string", "left (default), right, or middle. Right-clicks that would open a context menu are refused unless force is true."),
                "force": prop("boolean", "Allow a right-click that opens a context menu (it appears on the user's screen)."),
                "count": prop("integer", "2 for double-click. Default 1."),
                "method": prop("string", "auto (default), ax (accessibility only) or mouse (pointer events only)."),
            ])
        ),
        Tool(
            name: "drag",
            description: "Drag with the left button between two window-relative points, delivered to that window only.",
            inputSchema: schema([
                "user_window": userWindow,
                "window_id": windowID,
                "from_x": prop("number", ""), "from_y": prop("number", ""),
                "to_x": prop("number", ""), "to_y": prop("number", ""),
            ], required: ["window_id", "from_x", "from_y", "to_x", "to_y"])
        ),
        Tool(
            name: "scroll",
            description: "Scroll at a window-relative point (or an element). Uses the scroll area's scroll bars through accessibility when possible, otherwise wheel events to that window only. Negative dy scrolls down; values are points.",
            inputSchema: schema([
                "user_window": userWindow,
                "window_id": windowID,
                "element_id": elementID,
                "x": prop("number", ""), "y": prop("number", ""),
                "dx": prop("integer", "Default 0."), "dy": prop("integer", "Default -300 (scroll down)."),
                "method": prop("string", "auto (default), ax or mouse."),
            ])
        ),
        Tool(
            name: "screenshot",
            description: """
            Capture one window, even when it is covered, on another Space, or off screen. At scale 1, image pixels equal \
            window-relative points. With as_seen, capture instead exactly the part of the user's screen where that window \
            is, as the user sees it (whatever covers it, and backseat's green outline), never anything outside it. \
            macOS briefly shows its screen-recording indicator for any capture; prefer get_ui_tree or read_text when text is enough. \
            A window that isn't on the user's screen may not have been redrawn lately (browsers pause hidden windows), so its \
            screenshot can be out of date; the accessibility tree is always current.
            """,
            inputSchema: schema([
                "user_window": userWindow,
                "window_id": windowID,
                "as_seen": prop("boolean", "Capture the window's region of the user's screen as they see it, outline included. Only for windows visible on the user's current Space."),
                "scale": prop("number", "Pixels per point. Default 1; use 2 for Retina detail."),
                "format": prop("string", "png (default) or jpeg."),
            ], required: ["window_id"]),
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "select_menu_item",
            description: "Choose an item from an app's menu bar by path, e.g. [\"File\", \"New Window\"], without opening the menu on screen. Commands that only work while their app is active (Save, Bold, New Folder…) work too: backseat lends the app focus for a few dozen milliseconds without raising its windows or switching the user's Space, then gives it back. Reports any windows the command opened.",
            inputSchema: schema([
                "user_window": userWindow,
                "pid": pidProp,
                "window_id": prop("integer", "For commands that act on a window (Bold, Save…): the window to act on. Default: the app's main window."),
                "path": .object(["type": "array", "items": .object(["type": "string"]), "description": "Menu titles from the menu bar down. Matching ignores case and a trailing …"]),
            ], required: ["pid", "path"])
        ),
        Tool(
            name: "list_menu",
            description: "List an app's menu items with their enabled state and shortcuts. Without path, lists the menu bar's top-level menus.",
            inputSchema: schema([
                "pid": pidProp,
                "path": .object(["type": "array", "items": .object(["type": "string"]), "description": "Menu to list, e.g. [\"File\"] or [\"Format\", \"Font\"]."]),
            ], required: ["pid"]),
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "read_text",
            description: "The readable text of a window or element: headings marked with #, links as [text], field values, buttons as ‹label›. The page or document comes first, then sidebars, then window and browser controls, so max_chars never fills up with toolbar buttons. Good for web pages and documents.",
            inputSchema: schema([
                "user_window": userWindow,
                "window_id": windowID,
                "element_id": prop("string", "Only text under this element."),
                "max_chars": prop("integer", "Default 6000."),
            ]),
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "close_window",
            description: "Close a window with its own close button, without touching the app's other windows. The app may show a save sheet; check the window afterwards.",
            inputSchema: schema([
                "user_window": userWindow,"window_id": windowID], required: ["window_id"])
        ),
        Tool(
            name: "wait",
            description: "Wait until something happens in a window: text appears (text), text disappears (until gone), a web page finishes loading (until loaded), or the window stops changing (until settled). With neither, just sleeps ms.",
            inputSchema: schema([
                "user_window": userWindow,
                "ms": prop("integer", "Maximum time to wait. Default 10000 with a condition, 1000 without."),
                "window_id": windowID,
                "pid": prop("integer", "Use this app's main window when window_id is not given."),
                "text": prop("string", "Return as soon as an element whose label or value contains this appears (or, with until gone, disappears)."),
                "until": prop("string", "text (default when text is given), gone, loaded (web page done loading; returns its title and URL), or settled."),
            ])
        ),
        Tool(
            name: "clipboard",
            description: "Read the clipboard, or set it to text (pass text). Returns the clipboard's text afterwards.",
            inputSchema: schema(["text": prop("string", "Text to put on the clipboard. Omit to just read it.")])
        ),
        Tool(
            name: "batch",
            description: """
            Run several backseat calls in one go, in order, and get every result back: one round trip instead of many \
            (e.g. find a field, set its value, press return, read the result). Stops at the first error. In a step's args, \
            a string "$N" is replaced by the first element id (e12) in step N's result, so you can find and then act. \
            Screenshots and nested batches aren't allowed in a batch.
            """,
            inputSchema: schema([
                "steps": .object(["type": "array", "description": "Each step is {\"tool\": name, \"args\": {…}}.", "items": .object(["type": "object"])]),
                "continue_on_error": prop("boolean", "Keep going after a failed step. Default false."),
            ], required: ["steps"])
        ),
        Tool(
            name: "run_script",
            description: """
            Run AppleScript, JavaScript for Automation, or a zsh shell script. AppleScript results come back as source literals ({"a", "b"}, "text"). Apple Events reach an app in the background \
            without activating it, so this does what menu commands can't while the app isn't frontmost: make a Finder folder, \
            set text styles and save documents in TextEdit, and so on. Scripts that activate apps or fake input through \
            System Events (keystroke, key code, click) are refused. The first time a script talks to an app, macOS may ask the user \
            to allow it. Returns the script's result.
            """,
            inputSchema: schema([
                "script": prop("string", "The script source."),
                "language": prop("string", "applescript (default), javascript, or shell (zsh: list, move and read files without AppleScript)."),
                "timeout": prop("number", "Seconds before giving up. Default 20."),
                "allow_prompt": prop("boolean", "Run even if macOS would first ask the user to allow scripting that app. Default false: such scripts are refused so no permission dialog appears."),
            ], required: ["script"])
        ),
    ]

    static func call(_ name: String, _ args: Args) async throws -> Output {
        switch name {
        case "permissions": return permissions()
        case "list_apps": return listApps()
        case "list_windows": return listWindows(args)
        case "launch_app": return try await launchApp(args)
        case "get_ui_tree": return try uiTree(args)
        case "find_elements": return try findElements(args)
        case "element_info": return try elementInfo(args)
        case "perform_action": return try await performAction(args)
        case "set_value": return try await setValue(args)
        case "type_text": return try await typeText(args)
        case "press_key": return try await pressKey(args)
        case "click": return try await click(args)
        case "drag": return try await drag(args)
        case "scroll": return try await scroll(args)
        case "screenshot": return try await screenshot(args)
        case "select_menu_item": return try await selectMenuItem(args)
        case "wait": return try await wait(args)
        case "list_menu": return try listMenu(args)
        case "read_text": return try readText(args)
        case "close_window": return try await closeWindow(args)
        case "run_script": return try await runScript(args)
        case "clipboard": return clipboard(args)
        case "batch": return try await batch(args)
        default: throw ToolError("unknown tool '\(name)'")
        }
    }

    // MARK: Discovery

    static func permissions() -> Output {
        let ax = AXIsProcessTrusted()
        let screen = CGPreflightScreenCaptureAccess()
        var lines = [
            "accessibility: \(ax ? "granted" : "MISSING — needed for UI trees, clicks on elements, typing")",
            "screen recording: \(screen ? "granted" : "MISSING — needed for screenshot and window titles")",
        ]
        if !ax || !screen {
            lines.append("Grant these to the app that launches backseat (your terminal or MCP client) in System Settings → Privacy & Security, then restart it.")
        }
        return .text(lines.joined(separator: "\n"))
    }

    static func listApps() -> Output {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            .map { a in
                "pid=\(a.processIdentifier)  \(a.localizedName ?? "?")  \(a.bundleIdentifier ?? "-")"
                    + (a.processIdentifier == front ? "  [user's frontmost app]" : "")
                    + (a.isHidden ? "  [hidden]" : "")
            }
        return .text(apps.joined(separator: "\n"))
    }

    static func listWindows(_ args: Args) -> Output {
        let windows: [WindowInfo]
        if let pid = args.int("pid").map({ pid_t($0) }) {
            // The app's own windows, including off-screen ones and ones on other Spaces.
            windows = Windows.list(pid: pid)
        } else {
            // Everything on screen, minus menu-bar strips and other slivers.
            windows = Windows.withAXTitles(Windows.all(includeOffscreen: args.bool("include_offscreen") ?? false)
                .filter { $0.frame.width >= 50 && $0.frame.height >= 50 })
        }
        return .text(windows.isEmpty ? "no windows" : windows.map(\.line).joined(separator: "\n"))
    }

    static func launchApp(_ args: Args) async throws -> Output {
        let url: URL
        if let path = args.string("path") {
            url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else if let id = args.string("bundle_id"), let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            url = u
        } else if let name = args.string("name"), let u = appURL(named: name) {
            url = u
        } else if let target = args.string("url"), let u = openTarget(target), let app = NSWorkspace.shared.urlForApplication(toOpen: u) {
            url = app
        } else {
            throw ToolError("app not found; pass bundle_id, name, path, or url")
        }
        let document = args.string("url").flatMap(openTarget)

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        config.arguments = args.strings("arguments") ?? []
        // Several apps (Safari, System Settings) bring themselves forward while
        // launching even when asked not to; the guard hands focus straight back.
        FocusGuard.shared.expectLaunch(of: url)
        // If the app is already running, only windows this launch opens are the agent's.
        let running = NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
        let before = running.map { Set(Windows.list(pid: $0.processIdentifier).map(\.id)) }
        let app: NSRunningApplication
        if let document {
            app = try await NSWorkspace.shared.open([document], withApplicationAt: url, configuration: config)
        } else {
            app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
        FocusGuard.shared.touch(app.processIdentifier, seconds: 8)

        var windows: [WindowInfo] = []
        for _ in 0..<40 {
            windows = Windows.list(pid: app.processIdentifier)
            if let before {
                if windows.contains(where: { !before.contains($0.id) }) || document == nil { break }
            } else if !windows.isEmpty { break }
            try await Task.sleep(for: .milliseconds(125))
        }
        if let before {
            Ownership.shared.claim(windows.map(\.id).filter { !before.contains($0) })
        } else {
            Ownership.shared.claimApp(app.processIdentifier)
        }
        keepUserOnTop(windows)
        let list = windows.map(\.line).joined(separator: "\n")
        return .text("launched \(app.localizedName ?? url.lastPathComponent) pid=\(app.processIdentifier)\n\(list.isEmpty ? "no windows yet" : list)" + FocusGuard.shared.drainNotes(for: app.processIdentifier))
    }

    /// A URL from "https://…", "file://…", or a plain path.
    private static func openTarget(_ s: String) -> URL? {
        if s.contains("://") { return URL(string: s) }
        return URL(fileURLWithPath: (s as NSString).expandingTildeInPath)
    }

    private static func appURL(named name: String) -> URL? {
        let fm = FileManager.default
        let file = name.hasSuffix(".app") ? name : name + ".app"
        for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities", "~/Applications"] {
            let path = ((dir as NSString).expandingTildeInPath as NSString).appendingPathComponent(file)
            if fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    // MARK: Accessibility

    /// Resolves the root element and the window origin coordinates are relative to.
    private static func root(_ args: Args) throws -> (AXUIElement, CGPoint, String) {
        if let eid = args.string("element_id") {
            let e = try ElementStore.shared.get(eid)
            try Ownership.check(window: Ownership.window(of: e), pid: AX.pid(e), args, reading: true)
            let win = AX.containingWindow(e)
            let origin = win.flatMap(AX.frame)?.origin ?? .zero
            return (e, origin, "subtree of \(eid)")
        }
        if let wid = args.int("window_id") {
            let info = try Windows.get(CGWindowID(wid))
            guard let w = AX.window(id: info.id, pid: info.pid) else {
                throw ToolError("window \(wid) isn't one of the app's own windows; sheets and dialogs live inside their parent window's tree, so use list_windows with pid and the parent's id")
            }
            try Ownership.check(window: info.id, pid: info.pid, args, reading: true)
            Overlay.shared.highlight(info.id)
            return (w, AX.frame(w)?.origin ?? info.frame.origin, "window \(wid) (\(info.app))")
        }
        if let pid = args.int("pid") {
            let app = AX.app(pid_t(pid))
            let w = (AX.attr(app, kAXMainWindowAttribute) ?? AX.attr(app, kAXFocusedWindowAttribute)).map { $0 as! AXUIElement }
                ?? AX.windows(pid_t(pid)).first
            guard let w else { throw ToolError("pid \(pid) has no accessible windows") }
            try Ownership.check(window: AX.windowID(w), pid: pid_t(pid), args, reading: true)
            let id = AX.windowID(w).map { "window \($0)" } ?? "main window"
            return (w, AX.frame(w)?.origin ?? .zero, "\(id) of pid \(pid)")
        }
        throw ToolError("pass window_id, pid, or element_id")
    }

    static func uiTree(_ args: Args) throws -> Output {
        let (root, origin, what) = try root(args)
        let (nodes, truncated) = Tree.walk(
            root,
            maxDepth: args.int("max_depth") ?? 40,
            maxNodes: args.int("max_nodes") ?? 400,
            includeMenus: false,
            rowLimit: args.int("max_rows") ?? Tree.rowLimit
        )
        var text = "\(what); coordinates are window-relative points\n"
        text += nodes.map { $0.line(relativeTo: origin) }.joined(separator: "\n")
        if truncated { text += "\n… truncated; raise max_nodes/max_depth or pass element_id for a subtree" }
        return .text(text)
    }

    static func findElements(_ args: Args) throws -> Output {
        // With only a pid, search every window of the app, not just the main one.
        if args.int("window_id") == nil, args.string("element_id") == nil, let pid = args.int("pid") {
            var all: [String] = []
            var total = 0
            for w in Windows.list(pid: pid_t(pid)) {
                var a = args.raw; a["pid"] = nil; a["window_id"] = .int(Int(w.id))
                if case .text(let t) = try findElements(Args(a)), !t.hasPrefix("no matches") {
                    all.append(t); total += 1
                }
            }
            return .text(all.isEmpty ? "no matches in any window of pid \(pid)" : all.joined(separator: "\n"))
        }
        let (root, origin, what) = try root(args)
        let text = args.string("text")?.lowercased()
        let role = args.string("role").map(normalizeRole)
        guard text != nil || role != nil else { throw ToolError("pass text and/or role") }
        let limit = args.int("limit") ?? 30
        let (found, visited, complete) = Tree.search(root, text: text, role: role, limit: limit)
        if found.isEmpty {
            return .text(complete ? "no matches in \(what)"
                : "no matches in the first \(visited) elements of \(what) (stopped at the time limit; pass element_id to search one part)")
        }
        let lines = found.map { e -> String in
            var line = Tree.line(e, relativeTo: origin)
            // A bare label (sidebar row text, a button's caption): name what to act on.
            if !AX.isSettable(e, kAXValueAttribute), AX.howToAct(e) == nil, let (target, how) = AX.actionable(e) {
                line += "  → \(how) via \(describe(target, ElementStore.shared.add(target))): click \(ElementStore.shared.add(e)) does that"
            }
            return line
        }
        let header = complete ? "\(found.count) match(es) in \(what)"
            : "first \(found.count) match(es) in \(what) (stopped early; raise limit or pass element_id for more)"
        return .text(header + "\n" + lines.joined(separator: "\n"))
    }

    private static func normalizeRole(_ r: String) -> String {
        if r.hasPrefix("AX") { return r }
        let known = ["button", "textfield", "textarea", "checkbox", "radiobutton", "statictext", "link", "image",
                     "popupbutton", "menubutton", "combobox", "slider", "table", "row", "cell", "list", "window",
                     "scrollarea", "tabgroup", "toolbar", "group", "menuitem", "searchfield", "webarea", "outline"]
        let lower = r.lowercased().replacingOccurrences(of: " ", with: "")
        let map = ["textfield": "TextField", "textarea": "TextArea", "checkbox": "CheckBox", "radiobutton": "RadioButton",
                   "statictext": "StaticText", "popupbutton": "PopUpButton", "menubutton": "MenuButton", "combobox": "ComboBox",
                   "scrollarea": "ScrollArea", "tabgroup": "TabGroup", "menuitem": "MenuItem", "webarea": "WebArea"]
        if let m = map[lower] { return "AX" + m }
        if known.contains(lower) { return "AX" + lower.prefix(1).uppercased() + lower.dropFirst() }
        return "AX" + r.prefix(1).uppercased() + r.dropFirst()
    }

    static func elementInfo(_ args: Args) throws -> Output {
        let e = try ElementStore.shared.get(try args.require("element_id", args.string))
        try Ownership.check(window: Ownership.window(of: e), pid: AX.pid(e), args, reading: true)
        var names: CFArray?
        AXUIElementCopyAttributeNames(e, &names)
        var lines: [String] = ["pid=\(AX.pid(e))" + (AX.attr(e, kAXWindowAttribute).flatMap { AX.windowID($0 as! AXUIElement) }.map { " window=\($0)" } ?? "")]
        for name in (names as? [String] ?? []).sorted() {
            guard let v = AX.attr(e, name) else { continue }
            let desc: String
            switch v {
            case let s as String: desc = "\"\(s.clipped(name == kAXValueAttribute ? 4000 : 300))\""
            case let n as NSNumber: desc = n.stringValue
            case let a as [AnyObject]: desc = "[\(a.count) items]"
            default:
                if CFGetTypeID(v) == AXUIElementGetTypeID() { desc = "<element>" }
                else if CFGetTypeID(v) == AXValueGetTypeID() { desc = String(describing: v).components(separatedBy: "{value = ").last?.dropLast().description ?? "?" }
                else { desc = String(describing: v).truncated(120) }
            }
            lines.append("\(name)\(AX.isSettable(e, name) ? " (settable)" : ""): \(desc)")
        }
        lines.append("actions: " + AX.actions(e).map(AX.displayName(ofAction:)).joined(separator: ", "))
        // The raw AX attributes above are in global screen points; say where the
        // element is in the window-relative points every other tool uses.
        if let f = AX.frame(e), let w = AX.containingWindow(e), let o = AX.frame(w)?.origin {
            lines.append("(AXPosition/AXFrame above are global screen points. Window-relative, as get_ui_tree and click use: " +
                         "@(\(Int(f.minX - o.x)),\(Int(f.minY - o.y)) \(Int(f.width))x\(Int(f.height))))")
        }
        return .text(lines.joined(separator: "\n"))
    }

    static func performAction(_ args: Args) async throws -> Output {
        let id = try args.require("element_id", args.string)
        let e = try ElementStore.shared.get(id)
        try Ownership.check(window: Ownership.window(of: e), pid: AX.pid(e), args)
        let action = AX.resolveAction(args.string("action") ?? "press", on: e)
        if action == kAXPressAction { try AX.checkReachable(e, what: describe(e, id)) }
        if action == "AXShowMenu" && args.bool("force") != true {
            throw ToolError("showMenu pops a real menu up on the user's screen. Use select_menu_item for menu-bar commands, or pass force: true if you really need this context menu.")
        }
        let before = snapshot(of: e)
        let (outcome, note) = try await FocusGuard.run(target: AX.pid(e)) { () -> String in
            if action == kAXPressAction { return try AX.press(e, "\(action) on \(id)") }
            try AX.check(AXUIElementPerformAction(e, action as CFString), "\(action) on \(id)")
            return ""
        }
        let changed = outcome.isEmpty ? try await changes(since: before, expectMenu: action == "AXShowMenu") : ""
        return .text("performed \(AX.displayName(ofAction: action)) on \(describe(e, id))\(outcome)\(changed)\(note)")
    }

    private static func axAction(_ a: String) -> String {
        if a.hasPrefix("AX") { return a }
        return "AX" + a.prefix(1).uppercased() + a.dropFirst()
    }

    static func setValue(_ args: Args) async throws -> Output {
        let id = try args.require("element_id", args.string)
        let e = try ElementStore.shared.get(id)
        try Ownership.check(window: Ownership.window(of: e), pid: AX.pid(e), args)
        let attribute = args.string("attribute").map { $0.hasPrefix("AX") ? $0 : axAction($0) } ?? kAXValueAttribute
        let raw = args.raw["value"]
        let text: String
        if let s = raw?.stringValue { text = s }
        else if let i = raw?.intValue { text = String(i) }
        else if let d = raw?.doubleValue { text = String(d) }
        else if let b = raw?.boolValue { text = b ? "true" : "false" }
        else { throw ToolError("missing required argument 'value'") }

        let current = AX.attr(e, attribute)
        let value: CFTypeRef
        if let current, CFGetTypeID(current) == AXValueGetTypeID(), AXValueGetType(current as! AXValue) == .cfRange {
            // Ranges like AXSelectedTextRange: "start,length", "{0, 13}" or "0-13" style "start length".
            let nums = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            guard nums.count == 2 else { throw ToolError("\(attribute) is a range; pass \"location,length\", e.g. \"0,13\"") }
            var range = CFRange(location: nums[0], length: nums[1])
            value = AXValueCreate(.cfRange, &range)!
        } else if current is NSNumber || attribute == kAXFocusedAttribute || attribute == kAXSelectedAttribute {
            switch text.lowercased() {
            case "true", "yes", "on": value = kCFBooleanTrue
            case "false", "no", "off": value = kCFBooleanFalse
            default:
                guard let d = Double(text) else { throw ToolError("\(attribute) of \(id) is numeric; '\(text)' is not a number") }
                value = NSNumber(value: d)
            }
        } else {
            value = text as CFString
        }
        let (_, note) = try await FocusGuard.run(target: AX.pid(e)) {
            try AX.check(AXUIElementSetAttributeValue(e, attribute as CFString, value), "setting \(attribute) on \(id)")
        }
        // Read it back: some apps accept a write and ignore it.
        let after = AX.attr(e, attribute)
        // Long values were cut to 80 characters with "…", so a caller couldn't
        // tell the field holds all of what it sent. Say so outright instead.
        let shown: String
        if let str = after as? String, str.withoutDirectionMarks == text {
            shown = text.count <= 80 ? "\"\(text)\" (exactly as given)" : "exactly the \(text.count) characters given (\"\(text.clipped(60))\")"
        } else if let str = after as? String {
            shown = "\"\(str.withoutDirectionMarks.clipped(400))\"" + (attribute == kAXValueAttribute && !str.isEmpty ? " (not what was given: the app changed or trimmed it)" : "")
        } else {
            shown = after.map(describeValue) ?? "unreadable"
        }
        let unchanged = after != nil && current != nil && CFEqual(after, current) && !CFEqual(after, value)
        // A text field inside a list or table row is usually an inline editor
        // (renaming a file, a cell): the app only commits it on Return.
        var inRow = false
        var up = AX.attr(e, kAXParentAttribute).map { $0 as! AXUIElement }
        for _ in 0..<6 {
            guard let cur = up else { break }
            if ["AXRow", "AXCell", "AXOutline"].contains(AX.string(cur, kAXRoleAttribute) ?? "") { inRow = true; break }
            up = AX.attr(cur, kAXParentAttribute).map { $0 as! AXUIElement }
        }
        let commit = inRow && attribute == kAXValueAttribute
            ? "\n(this looks like an inline editor in a list row: the app hasn't saved it yet. press_key return with this element_id to commit it, then check the row)"
            : ""
        // Main and focused windows are per-app: setting them on a background app
        // reorders its windows, but it's still not the active app, so commands
        // that need a focused window (Save, Bold, New Folder) stay disabled.
        var inactive = ""
        if [kAXMainAttribute, kAXFocusedAttribute].contains(attribute), AX.string(e, kAXRoleAttribute) == kAXWindowRole,
           NSRunningApplication(processIdentifier: AX.pid(e))?.isActive != true {
            inactive = "\n(this only changes which window is \(attribute == kAXMainAttribute ? "main" : "focused") inside the app; the app is still in the background, so menu commands that need a focused window stay disabled. Use run_script or the window's own controls for those.)"
        }
        return .text("set \(attribute) of \(describe(e, id)); now \(shown)\(unchanged ? " — the app ignored the change" : "")\(commit)\(inactive)\(note)")
    }

    static func describeValue(_ v: AnyObject) -> String {
        switch v {
        case let s as String: return "\"\(s.withoutDirectionMarks.truncated(80))\""
        case let n as NSNumber: return n.stringValue
        default:
            if CFGetTypeID(v) == AXValueGetTypeID() {
                var r = CFRange()
                if AXValueGetValue(v as! AXValue, .cfRange, &r) { return "{\(r.location), \(r.length)}" }
            }
            return String(describing: v).truncated(80)
        }
    }

    static func typeText(_ args: Args) async throws -> Output {
        let text = try args.require("text", args.string)
        let method = args.string("method") ?? "auto"
        var element: AXUIElement?
        let pid: pid_t
        if let id = args.string("element_id") {
            let e = try ElementStore.shared.get(id)
            element = e
            pid = AX.pid(e)
        } else if let p = args.int("pid") {
            pid = pid_t(p)
            element = AX.attr(AX.app(pid), kAXFocusedUIElementAttribute).map { $0 as! AXUIElement }
        } else {
            throw ToolError("pass element_id or pid")
        }
        try Ownership.check(window: element.flatMap(Ownership.window(of:)), pid: pid, args)

        let (how, note) = try await FocusGuard.run(target: pid) { () -> String in
            if let element, args.string("element_id") != nil,
               (AX.attr(element, kAXFocusedAttribute) as? Bool) != true {
                AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                // Focusing selects everything; type at the end like a click would.
                var end = CFRange(location: (AX.valueString(element) ?? "").utf16.count, length: 0)
                if let range = AXValueCreate(.cfRange, &end) {
                    AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, range)
                }
            }
            if method != "keys", let element {
                if AX.isSettable(element, kAXSelectedTextAttribute),
                   AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
                    return "inserted via accessibility"
                }
                if method == "ax" {
                    guard AX.isSettable(element, kAXValueAttribute) else {
                        throw ToolError("element doesn't accept text through accessibility; try method \"keys\"")
                    }
                    let current = AX.valueString(element) ?? ""
                    try AX.check(AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, (current + text) as CFString), "appending text")
                    return "appended to value via accessibility"
                }
            } else if method == "ax" {
                throw ToolError("app has no focused text element; pass element_id")
            }
            guard AX.attr(AX.app(pid), kAXFocusedUIElementAttribute) != nil else {
                throw ToolError("nothing in this app has keyboard focus, so keystrokes would just beep. Pass element_id for the field to type into.")
            }
            Input.type(text, pid: pid)
            return "sent as key events to pid \(pid)"
        }
        return .text("typed \(text.count) character(s): \(how)\(note)")
    }

    /// The sheet or dialog keys sent now would land in: the one containing
    /// `element` (or the app's focused element), or a sheet open on its window.
    private static func dialog(around element: AXUIElement?, pid: pid_t) -> AXUIElement? {
        var e = element ?? AX.attr(AX.app(pid), kAXFocusedUIElementAttribute).map { $0 as! AXUIElement }
        for _ in 0..<40 {
            guard let cur = e else { return nil }
            let role = AX.string(cur, kAXRoleAttribute) ?? ""
            let subrole = AX.string(cur, kAXSubroleAttribute) ?? ""
            if role == "AXSheet" || subrole == "AXDialog" || subrole == "AXSystemDialog" { return cur }
            if role == "AXWindow" {
                return AX.elements(cur, kAXChildrenAttribute).last { AX.string($0, kAXRoleAttribute) == "AXSheet" }
            }
            e = AX.attr(cur, kAXParentAttribute).map { $0 as! AXUIElement }
        }
        return nil
    }

    /// The button Return or Escape would press in `dialog`.
    private static func dialogButton(_ dialog: AXUIElement, cancel: Bool) -> AXUIElement? {
        if let b = AX.attr(dialog, cancel ? kAXCancelButtonAttribute : kAXDefaultButtonAttribute), CFGetTypeID(b) == AXUIElementGetTypeID() {
            return (b as! AXUIElement)
        }
        let titles = cancel ? ["cancel", "close"] : ["save", "ok", "open", "go", "done", "choose", "replace"]
        var queue = AX.elements(dialog, kAXChildrenAttribute)
        var seen = 0
        while !queue.isEmpty, seen < 500 {
            let e = queue.removeFirst(); seen += 1
            if AX.string(e, kAXRoleAttribute) == "AXButton", (AX.attr(e, kAXEnabledAttribute) as? Bool) != false,
               titles.contains((AX.string(e, kAXTitleAttribute) ?? "").lowercased()) { return e }
            queue += AX.elements(e, kAXChildrenAttribute)
        }
        return nil
    }

    static func pressKey(_ args: Args) async throws -> Output {
        let combo = try args.require("key", args.string)
        let (code, flags) = try Input.parseCombo(combo)
        var pid: pid_t
        if let id = args.string("element_id") {
            let e = try ElementStore.shared.get(id)
            pid = AX.pid(e)
            try Ownership.check(window: Ownership.window(of: e), pid: pid, args)
            AXUIElementSetAttributeValue(e, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        } else if let p = args.int("pid") {
            pid = pid_t(p)
            let focused = AX.attr(AX.app(pid), kAXFocusedWindowAttribute).map { $0 as! AXUIElement }.flatMap(AX.windowID)
            try Ownership.check(window: focused, pid: pid, args)
        } else if let w = args.int("window_id") {
            pid = try Windows.get(CGWindowID(w)).pid
            try Ownership.check(window: CGWindowID(w), pid: pid, args)
        } else {
            throw ToolError("pass pid, window_id, or element_id")
        }

        // Shortcuts with ⌘ or ⌃ are menu commands. A background app rejects
        // the disabled ones with the alert sound, so never send those as keys:
        // choose the menu item directly, or refuse without making a sound.
        // Except inside a sheet or dialog: those handle their own shortcuts
        // (⌘⇧G is Go to Folder in a Save panel, but Find Previous in TextEdit's
        // menu bar), so keys typed there go to the dialog, not the menus.
        let target = args.string("element_id").flatMap { try? ElementStore.shared.get($0) }
            ?? args.int("window_id").flatMap { AX.window(id: CGWindowID($0), pid: pid) }
        // A background app's sheets and dialogs don't reliably get key events,
        // and Save/Open panels live in a separate process, so a key sent to the
        // app lands nowhere and it plays the alert sound. Do what the key would
        // do through accessibility instead, or refuse without sending anything.
        if let dialog = dialog(around: target, pid: pid) {
            let plain = !flags.contains(.maskCommand) && !flags.contains(.maskControl) && !flags.contains(.maskAlternate)
            let lower = combo.lowercased()
            if plain, ["return", "enter", "escape", "esc"].contains(lower) {
                let cancel = lower.hasPrefix("esc")
                if let button = dialogButton(dialog, cancel: cancel) {
                    let what = describe(button, ElementStore.shared.add(button))
                    let (outcome, note) = try await FocusGuard.run(target: pid) { try AX.press(button, "pressing \(what)") }
                    return .text("\(combo) in a dialog: pressed \(what) via accessibility\(outcome)\(note)")
                }
                // No button to press (Finder's Go to Folder has none): the key itself
                // is the only way, and it arrives when the target field has focus.
                guard let target, (AX.attr(target, kAXFocusedAttribute) as? Bool) == true else {
                    throw ToolError("\(combo) in this dialog: it has no \(cancel ? "Cancel" : "default") button, and no field in it has focus, so nothing was sent (it would just beep). Pass element_id for the dialog's field.")
                }
            } else {
                throw ToolError("""
                not sent: keys typed into a background app's sheet or dialog don't arrive (Save and Open panels run in a separate process), \
                and the app would just beep. Use the dialog's controls: set_value or type_text on its fields, click its buttons. \
                return and escape work here: they press the default and Cancel buttons.
                """)
            }
        }
        if flags.contains(.maskCommand) || flags.contains(.maskControl), let item = Menus.item(for: code, flags: flags, pid: pid) {
            let title = AX.string(item.element, kAXTitleAttribute) ?? combo
            if (AX.attr(item.element, kAXEnabledAttribute) as? Bool) == false {
                let window = args.int("window_id").map { CGWindowID($0) } ?? target.flatMap { AX.containingWindow($0) ?? $0 }.flatMap(AX.windowID)
                let outcome = try await runFocusOnly(item.element, pid: pid, window: window, name: item.path)
                return .text("\(combo) is \(item.path): \(outcome)")
            }
            let before = Set(Windows.list(pid: pid).map(\.id))
            let (_, note) = try await FocusGuard.run(target: pid) {
                try AX.press(item.element, "choosing \(title)")
            }
            let windows = try await newWindows(pid: pid, before: before)
            return .text("\(combo) is \(item.path); chose it from the menu\(windows)\(note)")
        }

        // Return in a window with a default button: press it through accessibility,
        // which a background app always accepts. (A field's own AXConfirm is not
        // a substitute: Finder's Go to Folder closes without going anywhere.)
        let plainKey = !flags.contains(.maskCommand) && !flags.contains(.maskControl) && !flags.contains(.maskAlternate)
        if plainKey, ["return", "enter"].contains(combo.lowercased()), let target,
           AX.string(target, kAXRoleAttribute) != "AXTextArea" {
            let what = describe(target, ElementStore.shared.add(target))
            if let window = AX.containingWindow(target) ?? (AX.string(target, kAXRoleAttribute) == "AXWindow" ? target : nil),
               let b = AX.attr(window, kAXDefaultButtonAttribute), CFGetTypeID(b) == AXUIElementGetTypeID() {
                let button = b as! AXUIElement
                let bw = describe(button, ElementStore.shared.add(button))
                let (outcome, note) = try await FocusGuard.run(target: pid) { try AX.press(button, "pressing \(bw)") }
                return .text("\(combo): pressed the default button \(bw) via accessibility\(outcome)\(note)")
            }
        }

        // Keys with nothing focused to receive them are rejected with the alert sound.
        let targetFocused = target.map { (AX.attr($0, kAXFocusedAttribute) as? Bool) == true } ?? false
        if !targetFocused, AX.attr(AX.app(pid), kAXFocusedUIElementAttribute) == nil {
            throw ToolError("nothing in this app has keyboard focus, so it would just beep. Pass element_id to focus the field or view first.")
        }
        let times = max(1, args.int("repeat") ?? 1)
        let before = Set(Windows.list(pid: pid).map(\.id))
        let (_, note) = try await FocusGuard.run(target: pid) {
            for _ in 0..<times {
                Input.key(code: code, flags: flags, pid: pid)
                usleep(15_000)
            }
        }
        // Return in a dialog can open a window (Finder's Go to Folder opens one).
        let windows = try await newWindows(pid: pid, before: before)
        return .text("pressed \(combo)\(times > 1 ? " ×\(times)" : "") in pid \(pid)\(windows)\(note)")
    }

    // MARK: Pointer

    /// Window and global point for element- or coordinate-based pointer tools.
    /// Window and window-relative point for element- or coordinate-based pointer tools.
    /// Window-relative means from the window's top-left as accessibility reports it,
    /// the same space get_ui_tree prints and screenshot (scale 1) shows.
    private static func target(_ args: Args, x xKey: String = "x", y yKey: String = "y") throws -> (WindowInfo, CGPoint, String) {
        if let id = args.string("element_id") {
            let e = try ElementStore.shared.get(id)
            guard let frame = AX.frame(e) else { throw ToolError("\(id) has no frame") }
            guard let axw = AX.containingWindow(e), let wid = AX.windowID(axw), let origin = AX.frame(axw)?.origin else {
                throw ToolError("can't find the window containing \(id)")
            }
            try Ownership.check(window: wid, pid: AX.pid(e), args)
            return (try Windows.get(wid), CGPoint(x: frame.midX - origin.x, y: frame.midY - origin.y), describe(e, id))
        }
        guard let wid = args.int("window_id") else { throw ToolError("pass element_id, or window_id with x and y") }
        let window = try Windows.get(CGWindowID(wid))
        try Ownership.check(window: window.id, pid: window.pid, args)
        let x = try args.require(xKey, args.number), y = try args.require(yKey, args.number)
        Overlay.shared.highlight(window.id)
        return (window, CGPoint(x: x, y: y), "(\(Int(x)),\(Int(y))) in window \(wid)")
    }

    /// "e12 (AXButton "Save")" so results say what was acted on.
    static func describe(_ e: AXUIElement, _ id: String) -> String {
        let role = AX.string(e, kAXRoleAttribute) ?? "element"
        let label = Tree.label(e)
        return label.isEmpty ? "\(id) (\(role))" : "\(id) (\(role) \"\(label.truncated(40))\")"
    }

    static func click(_ args: Args) async throws -> Output {
        let button = Input.Button(rawValue: args.string("button") ?? "left") ?? .left
        let count = args.int("count") ?? 1
        let method = args.string("method") ?? "auto"

        if let ids = args.strings("element_ids"), !ids.isEmpty {
            var done: [String] = []
            var note = ""
            for id in ids {
                let e = try ElementStore.shared.get(id)
                try Ownership.check(window: Ownership.window(of: e), pid: AX.pid(e), args)
                try AX.checkReachable(e, what: describe(e, id))
                let (outcome, n) = try await FocusGuard.run(target: AX.pid(e)) {
                    try AX.press(e, "press on \(describe(e, id)) after pressing \(done.count) of \(ids.count)")
                }
                done.append(describe(e, id) + outcome)
                note += n
            }
            return .text("pressed in order: " + done.joined(separator: ", ") + note)
        }

        // A plain click on something pressable is exact through accessibility.
        if method != "mouse", button == .left, count == 1 {
            if let (e, what, how) = try pressTarget(args) {
                let before = snapshot(of: e)
                let (outcome, note) = try await FocusGuard.run(target: AX.pid(e)) { () -> String in
                    if how == "select" {
                        try AX.check(AXUIElementSetAttributeValue(e, kAXSelectedAttribute as CFString, kCFBooleanTrue), "selecting \(what)")
                        guard (AX.attr(e, kAXSelectedAttribute) as? Bool) == true else {
                            throw ToolError("selecting \(what) didn't take: the app ignored it. Try click with method \"mouse\".")
                        }
                        return ""
                    }
                    return try AX.press(e, "press on \(what)")
                }
                let changed = outcome.isEmpty ? try await changes(since: before) : ""
                return .text("\(how == "select" ? "selected" : "pressed") \(what) via accessibility\(outcome)\(changed)\(note)")
            }
            if method == "ax" { throw ToolError("nothing pressable there; use method \"auto\" or \"mouse\"") }
        }
        let (window, point, what) = try target(args)
        // A right-click on something with a context menu pops a real menu up on
        // the user's screen, and the app sits in menu tracking (answering
        // nothing) until it's dismissed. Same rule as perform_action showMenu.
        if button == .right && args.bool("force") != true {
            var e = AX.element(at: point, in: window)
            for _ in 0..<4 {
                guard let cur = e else { break }
                if AX.actions(cur).contains("AXShowMenu") {
                    throw ToolError("""
                    a right-click there opens a context menu, which pops up on the user's screen and blocks the app until dismissed. \
                    Use the menu bar (select_menu_item) or the element's own actions instead, or pass force: true if you really need this menu.
                    """)
                }
                e = AX.attr(cur, kAXParentAttribute).map { $0 as! AXUIElement }
            }
        }
        if let hit = AX.element(at: point, in: window) {
            try AX.checkReachable(hit, what: "the \(AX.string(hit, kAXRoleAttribute) ?? "element") at \(what)")
        }
        let hit = AX.element(at: point, in: window)
        let before = snapshot(of: hit ?? AX.window(id: window.id, pid: window.pid), pid: window.pid)
        let (_, note) = try await FocusGuard.run(target: window.pid) {
            Input.click(at: point, window: window, button: button, count: count)
        }
        let changed = try await changes(since: before, expectMenu: button == .right)
        return .text("\(button.rawValue)-clicked \(what)\(count > 1 ? " ×\(count)" : "") via pointer events to window \(window.id)\(changed)\(note)")
    }

    /// What a plain click acts on through accessibility: the element (or the
    /// one at a point), or its nearest ancestor that can be pressed or selected
    /// (a label inside a button or list row). Nil if there's none.
    private static func pressTarget(_ args: Args) throws -> (AXUIElement, String, String)? {
        if let id = args.string("element_id") {
            let e = try ElementStore.shared.get(id)
            try Ownership.check(window: Ownership.window(of: e), pid: AX.pid(e), args)
            guard let (target, how) = AX.actionable(e) else { return nil }
            let what = CFEqual(target, e) ? describe(e, id)
                : "\(describe(target, ElementStore.shared.add(target))), the \(how == "select" ? "row" : "control") containing \(id)"
            try AX.checkReachable(target, what: what)
            return (target, what, how)
        }
        let (window, point, what) = try target(args)
        guard let hit = AX.element(at: point, in: window), let (target, how) = AX.actionable(hit) else { return nil }
        let desc = "\(AX.string(target, kAXRoleAttribute) ?? "element") \"\(Tree.label(target))\" at \(what)"
        try AX.checkReachable(target, what: desc)
        return (target, desc, how)
    }

    /// The state of an element's window before an action, to report what changed.
    struct Snapshot {
        let pid: pid_t
        let element: AXUIElement?
        let window: AXUIElement?
        let windows: Set<CGWindowID>
        let title: String?
        let sheet: Bool
        let digest: Int?
    }

    static func snapshot(of e: AXUIElement?, pid: pid_t? = nil) -> Snapshot {
        let pid = pid ?? e.map(AX.pid) ?? 0
        let window = e.flatMap(AX.containingWindow)
        return Snapshot(
            pid: pid, element: e, window: window,
            windows: Set(Windows.list(pid: pid).map(\.id)),
            title: window.flatMap { AX.string($0, kAXTitleAttribute) },
            sheet: window.map(hasSheet) ?? false,
            digest: window.map { AX.digest($0) }
        )
    }

    private static func hasSheet(_ w: AXUIElement) -> Bool {
        AX.elements(w, kAXChildrenAttribute).contains { AX.string($0, kAXRoleAttribute) == "AXSheet" }
    }

    /// What an action did, for its reply, so the caller needn't read the window
    /// again to find out: a menu that opened, new windows, a sheet, a new title,
    /// changed contents, or nothing visible. Waits up to ~300 ms for it to show.
    static func changes(since b: Snapshot, expectMenu: Bool = false) async throws -> String {
        let app = NSRunningApplication(processIdentifier: b.pid)
        var out: [String] = []
        for i in 0..<7 {
            if i > 0 { try await Task.sleep(for: .milliseconds(50)) }
            out = []
            if app?.isTerminated ?? true { return "\n→ the app quit" }
            let menus = AX.openMenus(pid: b.pid, near: b.element)
            if let menu = menus.first {
                let items = AX.elements(menu, kAXChildrenAttribute).compactMap { item -> String? in
                    let title = AX.string(item, kAXTitleAttribute) ?? ""
                    if title.isEmpty { return nil }
                    let off = (AX.attr(item, kAXEnabledAttribute) as? Bool) == false ? " [disabled]" : ""
                    return "\(ElementStore.shared.add(item)) \"\(title)\"\(off)"
                }
                let mid = ElementStore.shared.add(menu)
                return "\n→ a menu opened (it shows on the user's screen until closed): " + items.joined(separator: ", ")
                    + "\nclick an item's id to choose it, or perform_action cancel on \(mid) to close it."
            }
            let opened = Windows.list(pid: b.pid).filter { !b.windows.contains($0.id) }
            if !opened.isEmpty {
                Ownership.shared.claim(opened.map(\.id))
                keepUserOnTop(opened)
                out.append("new window(s):\n" + opened.map(\.line).joined(separator: "\n"))
            }
            if let w = b.window {
                var role: AnyObject?
                if AXUIElementCopyAttributeValue(w, kAXRoleAttribute as CFString, &role) == .invalidUIElement {
                    out.append("the window closed")
                } else {
                    if !b.sheet && hasSheet(w) { out.append("a sheet opened on the window (get_ui_tree shows it)") }
                    let title = AX.string(w, kAXTitleAttribute)
                    if title != b.title { out.append("the window is now titled \"\(title ?? "")\"") }
                    if out.isEmpty, let d = b.digest, AX.digest(w) != d { out.append("the window's contents changed") }
                }
            }
            if !out.isEmpty { break }
        }
        if out.isEmpty {
            return expectMenu ? "\n→ no menu appeared" : "\n→ no visible change in the window"
        }
        return "\n→ " + out.joined(separator: "\n→ ")
    }

    static func drag(_ args: Args) async throws -> Output {
        let (window, from, _) = try target(args, x: "from_x", y: "from_y")
        let (_, to, _) = try target(args, x: "to_x", y: "to_y")
        let (_, note) = try await FocusGuard.run(target: window.pid) {
            Input.drag(from: from, to: to, window: window)
        }
        return .text("dragged in window \(window.id) via pointer events\(note)")
    }

    static func scroll(_ args: Args) async throws -> Output {
        let (window, point, what) = try target(args)
        let dx = Int32(args.int("dx") ?? 0), dy = Int32(args.int("dy") ?? -300)
        let method = args.string("method") ?? "auto"

        if method != "mouse", let moved = try scrollWithAccessibility(args, point: point, window: window, dx: dx, dy: dy) {
            return .text("scrolled \(moved) via accessibility")
        }
        if method == "ax" { throw ToolError("no accessible scroll area at \(what)") }
        let (_, note) = try await FocusGuard.run(target: window.pid) {
            Input.scroll(at: point, dx: dx, dy: dy, window: window)
        }
        return .text("scrolled dx=\(dx) dy=\(dy) at \(what) via pointer events\(note)")
    }

    /// Moves the enclosing scroll area's scroll bars. Nil if there's no scroll area.
    private static func scrollWithAccessibility(_ args: Args, point: CGPoint, window: WindowInfo, dx: Int32, dy: Int32) throws -> String? {
        var e = AX.element(at: point, in: window)
        if let id = args.string("element_id") { e = try ElementStore.shared.get(id) }
        while let cur = e, AX.string(cur, kAXRoleAttribute) != kAXScrollAreaRole {
            e = AX.attr(cur, kAXParentAttribute).map { $0 as! AXUIElement }
        }
        guard let area = e else { return nil }
        let visible = AX.frame(area)?.size ?? .zero
        var content = AX.elements(area, kAXContentsAttribute).first.flatMap(AX.frame)?.size ?? .zero
        if content == .zero, let v = AX.attr(area, "AXContentSize"), CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgSize, &content)
        }
        var moved: [String] = []
        for (bar, delta, vis, total) in [(kAXVerticalScrollBarAttribute, -Double(dy), visible.height, content.height),
                                         (kAXHorizontalScrollBarAttribute, -Double(dx), visible.width, content.width)] where delta != 0 {
            guard let sb = AX.attr(area, bar).map({ $0 as! AXUIElement }),
                  let current = (AX.attr(sb, kAXValueAttribute) as? NSNumber)?.doubleValue,
                  AX.isSettable(sb, kAXValueAttribute) else { continue }
            let range = max(1, Double(total - vis))
            let next = min(1, max(0, current + delta / range))
            try AX.check(AXUIElementSetAttributeValue(sb, kAXValueAttribute as CFString, NSNumber(value: next)), "scrolling")
            moved.append(String(format: "%@ %.2f→%.2f", bar == kAXVerticalScrollBarAttribute ? "vertical" : "horizontal", current, next))
        }
        return moved.isEmpty ? nil : moved.joined(separator: ", ")
    }

    static func screenshot(_ args: Args) async throws -> Output {
        let wid = CGWindowID(try args.require("window_id", args.int))
        try Ownership.check(window: wid, pid: try Windows.get(wid).pid, args, reading: true)
        let scale = args.number("scale") ?? 1
        let shot = args.bool("as_seen") == true
            ? try Capture.asSeen(wid, scale: scale, format: args.string("format") ?? "png")
            : try await Capture.window(wid, scale: scale, format: args.string("format") ?? "png")
        // Apps stop drawing windows nobody can see (browsers especially), so a
        // capture of one shows whatever it last drew. Say so up front; the
        // accessibility tree is always current.
        let unseen = args.bool("as_seen") != true && (try? Windows.get(wid)).map { !Windows.visibleToUser($0) } ?? false
        return .image(shot.data, mime: shot.mime,
                      caption: "window \(wid): \(shot.width)x\(shot.height) px at scale \(scale); window-relative point = pixel / \(scale)"
                        + (unseen ? "\nThis window isn't on the user's screen, so the app may not have redrawn it lately and the image can be out of date. get_ui_tree and read_text always show its current state; check results there." : ""))
    }

    // MARK: Menus and waiting

    /// Windows `pid` opened since `before` was taken, as text for a tool's reply.
    /// Commands like New Window or Go to Folder finish asynchronously, so wait briefly.
    static func newWindows(pid: pid_t, before: Set<CGWindowID>) async throws -> String {
        let app = NSRunningApplication(processIdentifier: pid)
        var opened: [WindowInfo] = []
        for _ in 0..<12 {
            if app?.isTerminated ?? true { break }
            opened = Windows.list(pid: pid).filter { !before.contains($0.id) }
            if !opened.isEmpty { Ownership.shared.claim(opened.map(\.id)); break }
            try await Task.sleep(for: .milliseconds(40))
        }
        keepUserOnTop(opened)
        return opened.isEmpty ? "" : "\nnew window(s):\n" + opened.map(\.line).joined(separator: "\n")
    }

    /// Apps order new windows in front, even from the background, so a window an
    /// agent's command opens can land on top of what the user is doing. Raise the
    /// user's own window back above it: that reorders windows only; the user's
    /// app stays active and their focus doesn't move.
    static func keepUserOnTop(_ windows: [WindowInfo]) {
        guard let user = NSWorkspace.shared.frontmostApplication,
              windows.contains(where: { $0.pid != user.processIdentifier && Windows.visibleToUser($0) }),
              let mine = AX.attr(AX.app(user.processIdentifier), kAXFocusedWindowAttribute) else { return }
        AXUIElementPerformAction(mine as! AXUIElement, kAXRaiseAction as CFString)
    }

    /// Runs a menu command that AppKit only enables while its app is active
    /// (Bold, Save, New Folder…): lends the app focus for a moment without
    /// raising its windows or switching Spaces, opens the item's menu so AppKit
    /// re-validates it, presses it if it's really enabled, and hands focus back.
    /// Opening the menu first means a command that's unavailable even with focus
    /// (Undo with nothing to undo) is reported, never sent, so nothing beeps.
    static func runFocusOnly(_ item: AXUIElement, pid: pid_t, window: CGWindowID?, name: String) async throws -> String {
        // Lending focus takes the user's focus, however briefly; that is what
        // backseat exists to never do. Off unless explicitly enabled.
        guard ProcessInfo.processInfo.environment["BACKSEAT_ALLOW_FOCUS_BORROW"] == "1" else {
            throw ToolError("""
            '\(name)' only works while its app is active, and backseat never takes the user's focus. Nothing was sent. \
            Use the app's scripting (run_script), or the window's own controls.
            """)
        }
        // The menu bar item and every submenu item above `item`, top first: each
        // level has to open for AppKit to validate the items inside it.
        var levels: [AXUIElement] = []
        var up = AX.attr(item, kAXParentAttribute).map { $0 as! AXUIElement }
        while let cur = up {
            let role = AX.string(cur, kAXRoleAttribute)
            if role == "AXMenuItem" || role == "AXMenuBarItem" { levels.insert(cur, at: 0) }
            if role == "AXMenuBarItem" || role == "AXMenuBar" { break }
            up = AX.attr(cur, kAXParentAttribute).map { $0 as! AXUIElement }
        }
        let before = Set(Windows.list(pid: pid).map(\.id))
        let start = Date()
        let (result, borrowed) = try await FocusGuard.shared.borrow(pid: pid, window: window) { () -> String in
            for level in levels {
                AXUIElementPerformAction(level, kAXPressAction as CFString)
                try await Task.sleep(for: .milliseconds(5))
            }
            var enabled = false
            for _ in 0..<20 {
                if (AX.attr(item, kAXEnabledAttribute) as? Bool) == true { enabled = true; break }
                try await Task.sleep(for: .milliseconds(5))
            }
            guard enabled else {
                closeMenus(levels)
                throw ToolError("'\(name)' is disabled even with the app active: it doesn't apply right now (nothing selected, nothing to undo…). Nothing was sent. [debug: \(FocusGuard.shared.lastReadiness)]")
            }
            let outcome = try AX.press(item, "choosing \(name)")
            // Choosing an item in a submenu closes only that submenu: close every
            // menu we opened, or one stays on the user's screen and the app sits
            // in menu tracking, answering nothing.
            closeMenus(levels)
            for _ in 0..<10 where Windows.openMenuCount(pid: pid) > 0 {
                try await Task.sleep(for: .milliseconds(10))
                closeMenus(levels)
            }
            return outcome
        }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        let windows = try await newWindows(pid: pid, before: before)
        return "ran it" + result + (borrowed
            ? " (it only works while the app is active, so backseat lent it focus for \(ms) ms without raising its windows or switching Spaces, then gave focus back)"
            : "") + windows
    }

    /// Cancels the menus under these menu (bar) items, innermost first.
    private static func closeMenus(_ levels: [AXUIElement]) {
        for level in levels.reversed() {
            for menu in AX.elements(level, kAXChildrenAttribute) where AX.string(menu, kAXRoleAttribute) == "AXMenu" {
                AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            }
        }
    }

    static func selectMenuItem(_ args: Args) async throws -> Output {
        let pid = pid_t(try args.require("pid", args.int))
        let path = try args.require("path", args.strings)
        guard !path.isEmpty else { throw ToolError("path is empty") }
        if let w = args.int("window_id") { try Ownership.check(window: CGWindowID(w), pid: pid, args) }
        guard let bar = AX.attr(AX.app(pid), kAXMenuBarAttribute).map({ $0 as! AXUIElement }) else {
            throw ToolError("pid \(pid) has no menu bar")
        }

        func norm(_ s: String) -> String {
            s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .…"))
        }
        var items = AX.elements(bar, kAXChildrenAttribute)
        var current: AXUIElement?
        for (i, title) in path.enumerated() {
            let titles = items.map { AX.string($0, kAXTitleAttribute) ?? "" }
            guard let idx = titles.firstIndex(where: { norm($0) == norm(title) })
                    ?? titles.firstIndex(where: { norm($0).hasPrefix(norm(title)) }) else {
                let options = titles.filter { !$0.isEmpty }.joined(separator: ", ")
                throw ToolError("no menu item '\(title)' at level \(i + 1). Options: \(options)")
            }
            current = items[idx]
            if i < path.count - 1 {
                let submenu = AX.elements(items[idx], kAXChildrenAttribute).first
                items = submenu.map { AX.elements($0, kAXChildrenAttribute) } ?? []
            }
        }
        guard let item = current else { throw ToolError("empty path") }
        let name = path.joined(separator: " > ")
        if (AX.attr(item, kAXEnabledAttribute) as? Bool) == false {
            // AppKit sends menu commands to the focused window. A background app
            // has none, so commands that act on a document or window (Save, Bold,
            // Select All, New Folder) are disabled, and pressing them anyway does
            // nothing. App-level ones (New, Quit, Preferences) still work.
            let outcome = try await runFocusOnly(item, pid: pid, window: args.int("window_id").map { CGWindowID($0) }, name: name)
            return .text("\(name): \(outcome)")
        }
        let before = Set(Windows.list(pid: pid).map(\.id))
        let (outcome, note) = try await FocusGuard.run(target: pid) {
            try AX.press(item, "choosing menu item")
        }
        let app = NSRunningApplication(processIdentifier: pid)
        // Commands like New Window finish asynchronously; report what they opened.
        // Quit can also take a moment: say once the app has actually exited, so
        // the caller doesn't have to check list_apps.
        let windows = try await newWindows(pid: pid, before: before)
        let quit = outcome.isEmpty && (app?.isTerminated ?? true) ? " (the app quit)" : outcome
        return .text("chose \(name)\(quit)\(windows)\(note)")
    }

    static func listMenu(_ args: Args) throws -> Output {
        let pid = pid_t(try args.require("pid", args.int))
        guard let bar = AX.attr(AX.app(pid), kAXMenuBarAttribute).map({ $0 as! AXUIElement }) else {
            throw ToolError("pid \(pid) has no menu bar")
        }
        var items = AX.elements(bar, kAXChildrenAttribute)
        let path = args.strings("path") ?? []
        for title in path {
            let want = title.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .…"))
            guard let item = items.first(where: { (AX.string($0, kAXTitleAttribute) ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .…")).hasPrefix(want) }) else {
                throw ToolError("no menu '\(title)'. Options: " + items.compactMap { AX.string($0, kAXTitleAttribute) }.filter { !$0.isEmpty }.joined(separator: ", "))
            }
            items = AX.elements(item, kAXChildrenAttribute).first.map { AX.elements($0, kAXChildrenAttribute) } ?? []
        }
        let lines = items.compactMap { item -> String? in
            let title = AX.string(item, kAXTitleAttribute) ?? ""
            if title.isEmpty { return path.isEmpty ? nil : "—" }
            var line = title
            if let key = AX.string(item, kAXMenuItemCmdCharAttribute), !key.isEmpty {
                let mods = (AX.attr(item, kAXMenuItemCmdModifiersAttribute) as? Int) ?? 0
                // kAXMenuItemModifier flags: shift 1, option 2, control 4, no-command 8.
                var combo = ""
                if mods & 4 != 0 { combo += "ctrl+" }
                if mods & 2 != 0 { combo += "opt+" }
                if mods & 1 != 0 { combo += "shift+" }
                if mods & 8 == 0 { combo += "cmd+" }
                line += "  (\(combo)\(key.lowercased()))"
            }
            if !path.isEmpty, AX.elements(item, kAXChildrenAttribute).first != nil { line += "  ▸" }
            if (AX.attr(item, kAXEnabledAttribute) as? Bool) == false { line += "  [disabled]" }
            return line
        }
        return .text(lines.joined(separator: "\n"))
    }

    static func readText(_ args: Args) throws -> Output {
        let (root, _, what) = try root(args)
        let limit = args.int("max_chars") ?? 6000
        // Reading order, so controls never crowd content out of max_chars: the
        // page or document first, then sidebars (the narrower panes of a split
        // view), then window chrome (toolbars, title-bar buttons; in a browser,
        // everything outside the web page).
        let main = 0, side = 1, chrome = 2
        var parts: [[String]] = [[], [], []]
        var total = 0
        var visited = 0
        let browser = contains(root, role: "AXWebArea")
        func add(_ s: String, _ part: Int) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, parts[part].last != t else { return }
            parts[part].append(t)
            total += t.count
        }
        func visit(_ e: AXUIElement, depth: Int, part: Int, inWeb: Bool) {
            visited += 1
            guard total < limit * 4, depth < 80, visited < 20000 else { return }
            let role = AX.string(e, kAXRoleAttribute) ?? ""
            let part = browser && !inWeb && role != "AXWebArea" ? chrome : part
            switch role {
            case "AXMenuBar", "AXMenu", "AXScrollBar": return
            case "AXToolbar":
                for child in AX.elements(e, kAXChildrenAttribute) { visit(child, depth: depth + 1, part: chrome, inWeb: inWeb) }
                return
            case "AXWebArea":
                for child in AX.elements(e, kAXChildrenAttribute) { visit(child, depth: depth + 1, part: main, inWeb: true) }
                return
            case "AXSplitGroup" where part == main:
                // The widest pane is the content; the others are sidebars and inspectors.
                let panes = AX.elements(e, kAXChildrenAttribute).filter { AX.string($0, kAXRoleAttribute) != "AXSplitter" }
                let widest = panes.max { (AX.frame($0)?.width ?? 0) < (AX.frame($1)?.width ?? 0) }
                for pane in panes {
                    visit(pane, depth: depth + 1, part: widest.map { CFEqual($0, pane) } ?? true ? main : side, inWeb: inWeb)
                }
                return
            case "AXHeading":
                let level = (AX.attr(e, "AXDisclosureLevel") as? Int).map { $0 + 1 } ?? 2
                add(String(repeating: "#", count: min(max(level, 1), 6)) + " " + Tree.label(e), part); return
            case "AXLink": add("[\(Tree.label(e))]", part); return
            case "AXButton", "AXPopUpButton", "AXMenuButton":
                // Close, minimize, zoom and full-screen buttons are window chrome.
                let sub = AX.string(e, kAXSubroleAttribute) ?? ""
                let l = Tree.label(e); if !l.isEmpty { add("‹\(l)›", sub.hasSuffix("Button") && sub != "AXButton" ? chrome : part) }; return
            case "AXStaticText": add(AX.valueString(e) ?? Tree.label(e), part); return
            case "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox":
                let l = Tree.label(e), v = AX.valueString(e) ?? ""
                add(l.isEmpty ? v : "\(l): \(v)", part); return
            default: break
            }
            for child in AX.elements(e, kAXChildrenAttribute) { visit(child, depth: depth + 1, part: part, inWeb: inWeb) }
        }
        visit(root, depth: 0, part: main, inWeb: false)

        var text = ""
        var cut = false
        for (i, heading) in ["", "— sidebar —", browser ? "— browser controls —" : "— window controls —"].enumerated() where !parts[i].isEmpty {
            let body = parts[i].joined(separator: "\n")
            let room = limit - text.count
            if room <= 0 { cut = true; break }
            if !text.isEmpty { text += "\n\n" + heading + "\n" }
            if body.count > room { text += String(body.prefix(room)); cut = true; break }
            text += body
        }
        if cut || total >= limit * 4 { text += "\n… truncated; raise max_chars or pass element_id" }
        return .text(text.isEmpty ? "no text in \(what)" : text)
    }

    /// Whether `root` has a descendant with this role (searched breadth-first, bounded).
    private static func contains(_ root: AXUIElement, role: String) -> Bool {
        var queue = [root]
        var seen = 0
        while !queue.isEmpty, seen < 400 {
            let e = queue.removeFirst(); seen += 1
            if AX.string(e, kAXRoleAttribute) == role { return true }
            queue += AX.elements(e, kAXChildrenAttribute)
        }
        return false
    }

    static func clipboard(_ args: Args) -> Output {
        let pb = NSPasteboard.general
        if let text = args.string("text") {
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
        return .text(pb.string(forType: .string).map { "clipboard: \($0)" } ?? "clipboard has no text")
    }

    static func batch(_ args: Args) async throws -> Output {
        guard let steps = args.raw["steps"]?.arrayValue, !steps.isEmpty else { throw ToolError("steps must be a non-empty array") }
        let keepGoing = args.bool("continue_on_error") ?? false
        var results: [String] = []
        var lines: [String] = []
        for (i, step) in steps.enumerated() {
            guard let obj = step.objectValue, let tool = obj["tool"]?.stringValue else {
                throw ToolError("step \(i + 1) needs {\"tool\": name, \"args\": {…}}")
            }
            guard tool != "batch", tool != "screenshot" else { throw ToolError("step \(i + 1): \(tool) can't run inside a batch") }
            // "$N" -> first element id in step N's result.
            var stepArgs = obj["args"]?.objectValue ?? [:]
            for (k, v) in stepArgs {
                if let str = v.stringValue, str.hasPrefix("$"), let n = Int(str.dropFirst()), n >= 1, n <= results.count {
                    guard let id = results[n - 1].firstMatch(of: #/\be\d+\b/#) else {
                        throw ToolError("step \(i + 1): \(k) is \(str), but step \(n)'s result has no element id")
                    }
                    stepArgs[k] = .string(String(id.output))
                }
            }
            do {
                let out = try await call(tool, Args(stepArgs))
                let text: String
                switch out {
                case .text(let t): text = t
                case .image(_, _, let caption): text = caption
                }
                results.append(text)
                lines.append("\(i + 1). \(tool): \(text)")
            } catch {
                results.append("")
                lines.append("\(i + 1). \(tool) FAILED: \(error)")
                if !keepGoing {
                    if i + 1 < steps.count { lines.append("(stopped; \(steps.count - i - 1) step(s) not run)") }
                    break
                }
            }
        }
        return .text(lines.joined(separator: "\n"))
    }

    static func runScript(_ args: Args) async throws -> Output {
        let script = try args.require("script", args.string)
        let language = (args.string("language") ?? "applescript").lowercased()
        let js = language.hasPrefix("j")
        let shell = ["shell", "sh", "zsh", "bash"].contains(language)
        let timeout = args.number("timeout") ?? 20
        let lower = script.lowercased()
        // Anything that brings an app forward or types/clicks system-wide is
        // exactly what backseat exists to avoid.
        let banned = [#"\bactivate\b"#, #"\breopen\b"#, #"\bkeystroke\b"#, #"\bkey code\b"#, #"keyCode\("#, #"\.activate\("#]
        if let hit = banned.first(where: { lower.range(of: $0, options: .regularExpression) != nil }) {
            throw ToolError("refused: the script uses \(hit.replacingOccurrences(of: #"\b"#, with: "")), which would take the user's focus or keyboard. Address the app without activating it.")
        }
        // `open` brings the app it opens to the front unless told -g (background).
        if shell, let r = lower.range(of: #"(^|[\s;&|(])open\s+(?![^;&|\n]*\s-[a-z]*g)"#, options: .regularExpression), !lower[r].isEmpty {
            throw ToolError("refused: `open` without -g brings the app to the front. Use `open -g …` or launch_app.")
        }
        if lower.contains("system events") && lower.range(of: #"\bclick\b"#, options: .regularExpression) != nil {
            throw ToolError("refused: clicking through System Events moves the user's real pointer focus. Use click on an element instead.")
        }
        // The apps the script addresses: application "Name", application id "com.x",
        // Application("Name") in JavaScript.
        let names = Set(script.matches(of: #/(?:application|app|Application)\s*(?:id\s*)?\(?\s*"([^"]+)"/#).map { String($0.output.1).lowercased() })
        func named(_ a: NSRunningApplication) -> Bool {
            names.contains((a.localizedName ?? "").lowercased()) || names.contains((a.bundleIdentifier ?? "").lowercased())
        }
        // Controlling another app with Apple Events needs the user's permission,
        // and macOS asks with a dialog on their screen the first time, for each
        // app. Never set that dialog off: ask macOS first, without prompting.
        if !shell || lower.contains("osascript"), args.bool("allow_prompt") != true {
            for name in names where !NSWorkspace.shared.runningApplications.contains(where: {
                ($0.localizedName ?? "").lowercased() == name || ($0.bundleIdentifier ?? "").lowercased() == name
            }) {
                // The check needs the app running; start it in the background.
                if let url = appURL(named: name) ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = false
                    config.addsToRecentItems = false
                    FocusGuard.shared.expectLaunch(of: url)
                    if let launched = try? await NSWorkspace.shared.openApplication(at: url, configuration: config) {
                        Ownership.shared.claimApp(launched.processIdentifier)
                    }
                }
            }
            for app in NSWorkspace.shared.runningApplications where named(app) {
                guard let id = app.bundleIdentifier else { continue }
                let target = NSAppleEventDescriptor(bundleIdentifier: id)
                let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
                let appName = app.localizedName ?? id
                if status == OSStatus(errAEEventWouldRequireUserConsent) {
                    throw ToolError("""
                    not run: controlling \(appName) by script would make macOS show the user a permission dialog \
                    ("… wants access to control \(appName)"). Use backseat's accessibility tools on \(appName) instead. \
                    Pass allow_prompt: true only if the user has said they're fine being asked once.
                    """)
                }
                if status == OSStatus(errAEEventNotPermitted) {
                    throw ToolError("not run: the user hasn't allowed scripting \(appName) (System Settings › Privacy & Security › Automation). Use backseat's accessibility tools instead.")
                }
            }
        }

        // Arm the focus guard for every running app the script names.
        let pids = NSWorkspace.shared.runningApplications.filter(named).map(\.processIdentifier)
        for pid in pids { FocusGuard.shared.touch(pid, seconds: timeout + 2) }
        // Windows the script opens are the agent's; so is an app it launches.
        let windowsBefore = Dictionary(uniqueKeysWithValues: pids.map { ($0, Set(Windows.list(pid: $0).map(\.id))) })
        defer {
            for app in NSWorkspace.shared.runningApplications where named(app) {
                if let before = windowsBefore[app.processIdentifier] {
                    Ownership.shared.claim(Windows.list(pid: app.processIdentifier).map(\.id).filter { !before.contains($0) })
                } else {
                    Ownership.shared.claimApp(app.processIdentifier)
                }
            }
        }

        let proc = Process()
        if shell {
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-c", script]
        } else {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            // -ss prints results as source literals: lists keep their braces and
            // strings their quotes and escapes, instead of one flattened line.
            proc.arguments = (js ? ["-l", "JavaScript"] : ["-ss"]) + ["-e", script]
        }
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        // Drain both pipes while it runs, or a chatty script fills them and blocks.
        let outData = Task.detached { out.fileHandleForReading.readDataToEndOfFile() }
        let errData = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }
        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        if proc.isRunning {
            proc.terminate()
            throw ToolError("script timed out after \(Int(timeout))s (the app may be waiting on a dialog, or on the user to allow automation)")
        }
        try? await Task.sleep(for: .milliseconds(60))
        let notes = pids.map { FocusGuard.shared.drainNotes(for: $0) }.joined()
        let result = String(decoding: await outData.value, as: UTF8.self)
            .replacingOccurrences(of: "\r", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let error = String(decoding: await errData.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard proc.terminationStatus == 0 else {
            if error.contains("-1743") {
                throw ToolError("macOS hasn't allowed automating that app yet (System Settings → Privacy & Security → Automation). The user has to allow it.")
            }
            throw ToolError("script failed (exit \(proc.terminationStatus)): \(error.isEmpty ? result : error)")
        }
        return .text((result.isEmpty ? "ran; the script returned nothing (end it with `return …` to get a value back)" : result) + notes)
    }

    static func closeWindow(_ args: Args) async throws -> Output {
        let wid = CGWindowID(try args.require("window_id", args.int))
        let info = try Windows.get(wid)
        try Ownership.check(window: wid, pid: info.pid, args)
        guard let w = AX.window(id: wid, pid: info.pid) else { throw ToolError("window \(wid) isn't one of \(info.app)'s windows") }
        guard let button = AX.attr(w, kAXCloseButtonAttribute).map({ $0 as! AXUIElement }) else {
            throw ToolError("window \(wid) has no close button")
        }
        Overlay.shared.highlight(wid)
        let before = Set(Windows.list(pid: info.pid).map(\.id))
        let (_, note) = try await FocusGuard.run(target: info.pid) {
            try AX.press(button, "closing window \(wid)")
        }
        // Return as soon as it's gone, or as soon as the app asks something (a save
        // prompt comes as a sheet on the window or as a window of its own).
        for _ in 0..<25 {
            let now = Windows.list(pid: info.pid)
            if !now.contains(where: { $0.id == wid }) { return .text("closed window \(wid)\(note)") }
            let prompts = now.filter { !before.contains($0.id) }
            if !prompts.isEmpty {
                return .text("window \(wid) is still open: the app is asking first, in\n" + prompts.map(\.line).joined(separator: "\n") + note)
            }
            if AX.elements(w, kAXChildrenAttribute).contains(where: { AX.string($0, kAXRoleAttribute) == "AXSheet" }) {
                return .text("window \(wid) is still open: the app is asking first, in a sheet on it (find it with get_ui_tree)\(note)")
            }
            try await Task.sleep(for: .milliseconds(40))
        }
        return .text("pressed close on window \(wid), but it's still open\(note)")
    }

    static func wait(_ args: Args) async throws -> Output {
        let text = args.string("text")?.lowercased()
        let until = args.string("until")?.lowercased() ?? (text == nil ? "" : "text")
        let hasTarget = args.int("window_id") != nil || args.int("pid") != nil || args.string("element_id") != nil
        let ms = args.int("ms") ?? (until.isEmpty ? 1000 : 10_000)
        guard !until.isEmpty, hasTarget else {
            if !until.isEmpty { throw ToolError("pass window_id or pid with until/text") }
            try await Task.sleep(for: .milliseconds(ms))
            return .text("waited \(ms) ms")
        }
        let start = Date()
        let deadline = start.addingTimeInterval(Double(ms) / 1000)
        func elapsed() -> Int { Int(Date().timeIntervalSince(start) * 1000) }
        func matching(_ root: AXUIElement, _ t: String) -> (match: AXUIElement?, complete: Bool) {
            let r = Tree.search(root, text: t, role: nil, limit: 1, budget: 3)
            return (r.matches.first, r.complete)
        }
        var lastDigest: Int?
        var stableSince = Date()
        repeat {
            let (root, origin, what) = try root(args)
            switch until {
            case "text":
                guard let text else { throw ToolError("until text needs text") }
                if let e = matching(root, text).match {
                    return .text("found after \(elapsed()) ms: " + Tree.line(e, relativeTo: origin))
                }
            case "gone":
                guard let text else { throw ToolError("until gone needs text") }
                // A search cut short by its time limit proves nothing.
                let r = matching(root, text)
                if r.match == nil && r.complete { return .text("\"\(text)\" is gone from \(what) after \(elapsed()) ms") }
            case "loaded":
                // Web pages: not busy, marked loaded, and the page stopped
                // changing for a moment (a click may not have started loading yet).
                let webs = webAreas(root)
                guard !webs.isEmpty else { throw ToolError("\(what) has no web page; use until settled") }
                let busy = webs.contains { (AX.attr($0, "AXElementBusy") as? Bool) == true || (AX.attr($0, "AXLoaded") as? Bool) == false }
                let d = AX.digest(root, limit: 1500)
                if busy || d != lastDigest { lastDigest = d; stableSince = Date() }
                else if Date().timeIntervalSince(stableSince) >= 0.4 {
                    let page = webs.first.map { w -> String in
                        let title = Tree.label(w)
                        let url = (AX.attr(w, "AXURL") as? URL)?.absoluteString ?? ""
                        return [title.isEmpty ? nil : "\"\(title)\"", url.isEmpty ? nil : url].compactMap { $0 }.joined(separator: " ")
                    } ?? ""
                    return .text("page loaded after \(elapsed()) ms\(page.isEmpty ? "" : ": \(page)")")
                }
            case "settled":
                let d = AX.digest(root, limit: 1500)
                if d != lastDigest { lastDigest = d; stableSince = Date() }
                else if Date().timeIntervalSince(stableSince) >= 0.4 {
                    return .text("\(what) stopped changing after \(elapsed()) ms")
                }
            default:
                throw ToolError("until is text, gone, loaded or settled")
            }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        switch until {
        case "loaded": return .text("timed out after \(ms) ms; the page is still loading or still changing")
        case "settled": return .text("timed out after \(ms) ms; the window is still changing")
        case "gone": return .text("timed out after \(ms) ms; \"\(text ?? "")\" is still there")
        default: return .text("timed out after \(ms) ms; nothing matching \"\(text ?? "")\"")
        }
    }

    private static func webAreas(_ root: AXUIElement) -> [AXUIElement] {
        var found: [AXUIElement] = []
        var queue = [root]
        var seen = 0
        while !queue.isEmpty, seen < 600 {
            let e = queue.removeFirst(); seen += 1
            if AX.string(e, kAXRoleAttribute) == "AXWebArea" { found.append(e); continue }
            queue += AX.elements(e, kAXChildrenAttribute)
        }
        return found
    }
}
