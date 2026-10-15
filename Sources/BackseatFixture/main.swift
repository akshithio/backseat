// A small AppKit app for the end-to-end tests. It never activates itself and
// writes everything that happens to it to a JSON file, so tests can check
// what backseat did without trusting backseat's own reading of the UI.
import AppKit

let statePath = CommandLine.arguments.dropFirst().first ?? "/tmp/backseat-fixture.json"

final class State {
    static var values: [String: Any] = [
        "count": 0, "clicks": 0, "rightClicks": 0, "doubleClicks": 0, "lastClick": [0, 0],
        "drag": [0, 0, 0, 0], "scrollY": 0.0, "keys": "", "text": "", "keysText": "",
        "checked": false, "slider": 0.0, "menuResets": 0, "becameActive": 0,
    ]

    static func set(_ key: String, _ value: Any) {
        values[key] = value
        if let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: statePath))
        }
    }

    static func bump(_ key: String) { set(key, (values[key] as? Int ?? 0) + 1) }
}

/// Records clicks, double-clicks, right-clicks and drags with view-local coordinates (top-left origin).
final class ClickPad: NSView {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var dragStart: NSPoint?

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemTeal.withAlphaComponent(0.3).setFill()
        bounds.fill()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragStart = p
        State.bump("clicks")
        if event.clickCount == 2 { State.bump("doubleClicks") }
        State.set("lastClick", [Int(p.x.rounded()), Int(p.y.rounded())])
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let s = dragStart, hypot(p.x - s.x, p.y - s.y) > 5 {
            State.set("drag", [Int(s.x), Int(s.y), Int(p.x), Int(p.y)])
        }
        dragStart = nil
    }

    override func rightMouseDown(with event: NSEvent) { State.bump("rightClicks") }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Click Pad" }
}

/// Logs raw key events it receives while it is the first responder.
final class KeyField: NSTextField {
    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        State.set("keysText", stringValue)
    }
}

final class Controller: NSObject, NSTextFieldDelegate, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let window = FixtureWindow(contentRect: NSRect(x: 60, y: 120, width: 480, height: 560),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    let countLabel = NSTextField(labelWithString: "count: 0")
    let input = NSTextField(string: "")
    let keyField = KeyField(string: "")
    let checkbox = NSButton(checkboxWithTitle: "Enable thing", target: nil, action: nil)
    let slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    let scroll = NSScrollView()
    var probe: NSPanel?
    // Rows whose only text is a bare label, like a sidebar: the label itself
    // can't be pressed, its row is selected instead.
    let rows = ["Alpha", "Beta", "Gamma"]
    let table = NSTableView()

    func applicationDidFinishLaunching(_ note: Notification) {
        window.title = "Backseat Fixture"
        window.delegate = self
        window.isReleasedWhenClosed = false
        let root = NSView()
        window.contentView = root

        let button = NSButton(title: "Increment", target: self, action: #selector(increment))
        input.placeholderString = "Name"
        input.setAccessibilityIdentifier("input")
        input.delegate = self
        keyField.placeholderString = "Keys"
        keyField.setAccessibilityIdentifier("keys")
        checkbox.target = self; checkbox.action = #selector(toggled)
        slider.target = self; slider.action = #selector(slid)
        slider.setAccessibilityLabel("Level")

        let disabled = NSButton(title: "Unavailable", target: self, action: #selector(unavailable))
        disabled.isEnabled = false
        let pad = ClickPad()
        let doc = FlippedView(frame: NSRect(x: 0, y: 0, width: 200, height: 2000))
        scroll.documentView = doc
        scroll.hasVerticalScroller = true
        scroll.setAccessibilityLabel("Scroller")
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)

        let column = NSTableColumn(identifier: .init("name"))
        column.width = 380
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("Places")
        let tableScroll = NSScrollView()
        tableScroll.documentView = table

        // Plain frames (top-left layout) so tests know where things are.
        let items: [(NSView, NSRect)] = [
            (button, NSRect(x: 20, y: 20, width: 120, height: 30)),
            (disabled, NSRect(x: 300, y: 20, width: 120, height: 30)),
            (countLabel, NSRect(x: 160, y: 25, width: 120, height: 20)),
            (input, NSRect(x: 20, y: 60, width: 200, height: 24)),
            (keyField, NSRect(x: 240, y: 60, width: 200, height: 24)),
            (checkbox, NSRect(x: 20, y: 95, width: 200, height: 20)),
            (slider, NSRect(x: 240, y: 95, width: 200, height: 20)),
            (pad, NSRect(x: 20, y: 130, width: 200, height: 200)),
            (scroll, NSRect(x: 240, y: 130, width: 200, height: 200)),
            (tableScroll, NSRect(x: 20, y: 345, width: 420, height: 90)),
        ]
        let flipped = FlippedView(frame: NSRect(x: 0, y: 0, width: 480, height: 560))
        flipped.autoresizingMask = [.width, .height]
        root.addSubview(flipped)
        for (view, frame) in items {
            view.frame = frame
            flipped.addSubview(view)
        }

        let menu = NSMenu()
        let appItem = NSMenuItem(); appItem.submenu = NSMenu(title: "BackseatFixture")
        appItem.submenu?.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fixtureItem = NSMenuItem(); fixtureItem.submenu = NSMenu(title: "Fixture")
        fixtureItem.submenu?.addItem(withTitle: "Reset Counter", action: #selector(reset), keyEquivalent: "r").target = self
        // Like Save in a real app: only enabled when a window has focus.
        let needs = NSMenuItem(title: "Needs Focus", action: #selector(needsFocus), keyEquivalent: "d")
        needs.keyEquivalentModifierMask = [.command, .shift]
        needs.target = self
        fixtureItem.submenu?.addItem(needs)
        fixtureItem.submenu?.addItem(withTitle: "Show Sheet", action: #selector(showSheet), keyEquivalent: "").target = self
        // Like Bold or Save in a real app: no target, so AppKit sends it to the
        // first responder of the key window. With the app in the background there
        // is no key window, so AppKit disables it. The hard case.
        let focusOnly = NSMenuItem(title: "Focus Only", action: #selector(FixtureWindow.focusOnly(_:)), keyEquivalent: "f")
        focusOnly.keyEquivalentModifierMask = [.command, .shift]
        fixtureItem.submenu?.addItem(focusOnly)
        // Like File > New in most apps: opens a window, ordered in front, on the user's Space.
        fixtureItem.submenu?.addItem(withTitle: "New Window", action: #selector(newWindow), keyEquivalent: "").target = self
        // Like a browser's New Window: the new window becomes the app's key and
        // main window, the one the user lands in when they next switch to the app.
        fixtureItem.submenu?.addItem(withTitle: "New Key Window", action: #selector(newKeyWindow), keyEquivalent: "").target = self
        // Like Finder's New Finder Window: a command that activates the app itself.
        fixtureItem.submenu?.addItem(withTitle: "Bring To Front", action: #selector(bringToFront), keyEquivalent: "").target = self
        menu.addItem(appItem); menu.addItem(fixtureItem)
        NSApp.mainMenu = menu

        // Accessibility writes don't fire delegate callbacks, so poll too.
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let snapshot: [String: Any] = [
                "text": input.stringValue, "keysText": keyField.stringValue,
                "checked": checkbox.state == .on, "slider": slider.doubleValue,
                "isKey": window.isKeyWindow, "appActive": NSApp.isActive,
                "mainTitle": NSApp.mainWindow?.title ?? "", "keyTitle": NSApp.keyWindow?.title ?? "",
            ]
            for (k, v) in snapshot where !(State.values[k] as AnyObject).isEqual(v) { State.set(k, v) }
        }

        if CommandLine.arguments.contains("--visible") {
            // A normal window on the user's current Space, like a real app's.
            window.setFrameOrigin(NSPoint(x: 60, y: 60))
        }
        if CommandLine.arguments.contains("--onscreen") {
            // On the user's screen (any Space, full-screen ones included) but
            // almost invisible and click-through: for checking the highlight.
            window.alphaValue = 0.02
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.setFrameOrigin(NSPoint(x: 40, y: 40))
            // A background app's windows can't appear over someone's
            // full-screen app, but a non-activating panel can (backseat's own
            // outline is one). It gives the outline something to land on.
            let probe = NSPanel(contentRect: NSRect(x: 40, y: 40, width: 220, height: 90),
                                styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
            probe.title = "Outline Probe"
            probe.hidesOnDeactivate = false
            probe.isReleasedWhenClosed = false
            probe.level = .floating
            // Fully visible: backseat never outlines a window the user can't see.
            probe.ignoresMouseEvents = true
            probe.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            probe.contentView?.addSubview(NSButton(frame: NSRect(x: 20, y: 25, width: 120, height: 30)).then {
                $0.title = "Probe"; $0.bezelStyle = .rounded
            })
            probe.orderFrontRegardless()
            self.probe = probe
        }
        let otherSpace = CommandLine.arguments.contains("--other-space")
        if CommandLine.arguments.contains("--invisible") || otherSpace {
            // For running the tests while someone is using the Mac: nearly
            // transparent, off every display, and present on every Space
            // (full-screen ones included) so nothing ever switches Spaces to reach it.
            window.alphaValue = 0.02
            if !otherSpace { window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] }
            // Park it beyond every display so the user's real clicks can't land on it.
            let far = NSScreen.screens.map(\.frame).reduce(NSRect.zero) { $0.union($1) }.maxX + 2000
            window.unconstrained = true
            window.setFrameOrigin(NSPoint(x: far, y: 200))
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if otherSpace && self.window.isOnActiveSpace {
                // The user is on the Space the window opened on; take it off
                // that Space so it's somewhere they aren't looking.
                let cid = CGSMainConnectionID()
                CGSRemoveWindowsFromSpaces(cid, [NSNumber(value: self.window.windowNumber)] as CFArray,
                                           [NSNumber(value: CGSGetActiveSpace(cid))] as CFArray)
                State.set("spaceMode", "detached from the user's Space")
            } else if otherSpace {
                State.set("spaceMode", "opened on a Space the user isn't on")
            }
            State.set("onActiveSpace", self.window.isOnActiveSpace)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            State.set("onActiveSpace", self.window.isOnActiveSpace)
        }
        window.makeFirstResponder(keyField)
        State.set("visible", window.isVisible)
        State.set("ready", true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { State.set("visibleLater", self.window.isVisible); State.set("occl", Int(self.window.occlusionState.rawValue)) }
    }

    /// Activates the app the forceful way Finder and Safari manage to:
    /// NSApp.activate is refused for a background app since macOS 14.
    @objc func bringToFront() {
        typealias SetFront = @convention(c) (UnsafePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32
        typealias GetPSN = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
        var psn = ProcessSerialNumber()
        if let sl = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
           let set = dlsym(sl, "_SLPSSetFrontProcessWithOptions"),
           let asv = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW),
           let get = dlsym(asv, "GetProcessForPID"),
           unsafeBitCast(get, to: GetPSN.self)(getpid(), &psn) == noErr {
            _ = unsafeBitCast(set, to: SetFront.self)(&psn, UInt32(window.windowNumber), 0x200)
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    @objc func unavailable() { State.bump("unavailablePressed") }
    @objc func needsFocus() { State.bump("needsFocusRan") }

    let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
    var extraWindows: [NSWindow] = []
    @objc func newKeyWindow() {
        let w = FixtureWindow(contentRect: NSRect(x: 80, y: 80, width: 260, height: 160), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Fixture Key Extra"
        w.isReleasedWhenClosed = false
        w.unconstrained = window.unconstrained
        w.alphaValue = window.alphaValue
        w.collectionBehavior = window.collectionBehavior
        w.setFrameOrigin(NSPoint(x: window.frame.minX, y: window.frame.minY))
        w.makeKeyAndOrderFront(nil)
        w.makeMain()
        extraWindows.append(w)
        State.bump("keyWindows")
    }
    @objc func newWindow() {
        let w = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 260, height: 160), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Fixture Extra"
        w.isReleasedWhenClosed = false
        w.orderFrontRegardless()
        extraWindows.append(w)
        State.bump("extraWindows")
    }
    @objc func showSheet() {
        let close = NSButton(title: "Close Sheet", target: self, action: #selector(closeSheet))
        close.frame = NSRect(x: 70, y: 30, width: 120, height: 30)
        close.keyEquivalent = "\r"  // the default button, like Save in a Save panel
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelSheet))
        cancel.frame = NSRect(x: 70, y: 70, width: 120, height: 30)
        cancel.keyEquivalent = "\u{1b}"
        sheet.contentView?.subviews.forEach { $0.removeFromSuperview() }
        sheet.contentView?.addSubview(close)
        sheet.contentView?.addSubview(cancel)
        window.beginSheet(sheet)
        State.set("sheetOpen", true)
    }
    @objc func cancelSheet() {
        State.bump("sheetCancels")
        closeSheet()
    }
    @objc func closeSheet() {
        window.endSheet(sheet)
        State.set("sheetOpen", false)
    }

    func applicationDidBecomeActive(_ note: Notification) { State.bump("becameActive") }
    func windowDidBecomeKey(_ note: Notification) { State.bump("becameKey") }

    @objc func increment() {
        State.bump("count")
        countLabel.stringValue = "count: \(State.values["count"]!)"
    }
    @objc func reset() {
        State.set("count", 0)
        State.bump("menuResets")
        countLabel.stringValue = "count: 0"
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(needsFocus) ? NSApp.keyWindow != nil : true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: rows[row])
        label.frame = NSRect(x: 4, y: 2, width: 300, height: 18)
        cell.addSubview(label)
        cell.textField = label
        return cell
    }
    func tableViewSelectionDidChange(_ note: Notification) {
        State.set("selectedRow", table.selectedRow >= 0 ? rows[table.selectedRow] : "")
    }

    @objc func toggled() { State.set("checked", checkbox.state == .on) }
    @objc func slid() { State.set("slider", slider.doubleValue) }
    @objc func scrolled() { State.set("scrollY", Double(scroll.contentView.bounds.origin.y)) }

    func controlTextDidChange(_ note: Notification) { State.set("text", input.stringValue) }
}

// Private Spaces API, only used to take the test window off the user's Space.
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSGetActiveSpace") func CGSGetActiveSpace(_ cid: Int32) -> UInt64
@_silgen_name("CGSRemoveWindowsFromSpaces") func CGSRemoveWindowsFromSpaces(_ cid: Int32, _ windows: CFArray, _ spaces: CFArray)

/// Lets the invisible test window live beyond every display; AppKit would
/// otherwise pull a titled window back on screen.
final class FixtureWindow: NSWindow {
    var unconstrained = false
    @objc func focusOnly(_ sender: Any?) { State.bump("focusOnlyRan") }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        unconstrained ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// --probe: block every activation path and log who asked, so pointer-event
/// experiments can never take the user's focus.
func installActivationProbe() {
    // Only the calls that ask WindowServer to make the app frontmost; AppKit's
    // own handling of an activation event is left alone so it can be observed.
    let selectors = ["activate", "activateIgnoringOtherApps:", "activateUsingEvent:", "_activateWithInfo:"]
    for name in selectors {
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(NSApplication.self, sel) else { continue }
        let block: @convention(block) (AnyObject, AnyObject?) -> Void = { _, _ in
            var log = State.values["activationAttempts"] as? [String] ?? []
            let caller = Thread.callStackSymbols.dropFirst(1).prefix(8)
                .map { $0.split(separator: " ", omittingEmptySubsequences: true).dropFirst(3).prefix(1).joined() }
            log.append(name + " <- " + caller.joined(separator: " <- "))
            State.set("activationAttempts", log)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}

/// A regular app, like the ones backseat drives, but one that never bounces in
/// the Dock: tests open sheets in it while it's in the background, and AppKit
/// would otherwise bounce its icon at the user until the sheet closed.
final class FixtureApplication: NSApplication {
    override func requestUserAttention(_ requestType: NSApplication.RequestUserAttentionType) -> Int { 0 }
}
let app = FixtureApplication.shared
// Count every key event the app receives: a refused shortcut must send none.
NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { e in
    State.bump("keyDowns")
    return e
}
if CommandLine.arguments.contains("--probe") {
    installActivationProbe()
    NSEvent.addLocalMonitorForEvents(matching: .any) { e in
        if e.type != .appKitDefined && e.type != .systemDefined && e.type != .periodic {
            var log = State.values["events"] as? [String] ?? []
            let loc = e.locationInWindow
            let where_ = loc.x.isFinite && loc.y.isFinite ? "\(Int(loc.x)),\(Int(loc.y))" : "-"
            log.append("\(e.type.rawValue) win=\(e.windowNumber) loc=\(where_) hasWin=\(e.window != nil)")
            State.set("events", Array(log.suffix(20)))
        }
        return e
    }
}
let controller = Controller()
app.delegate = controller
app.setActivationPolicy(.regular)
// Its Dock icon while tests run: a test tube, so it's clearly backseat's test app.
app.applicationIconImage = NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rect in
    NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.33, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: 50, dy: 50), xRadius: 90, yRadius: 90).fill()
    let config = NSImage.SymbolConfiguration(pointSize: 230, weight: .semibold).applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "testtube.2", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height))
    }
    return true
}
app.run()

extension NSObjectProtocol {
    func then(_ f: (Self) -> Void) -> Self { f(self); return self }
}
