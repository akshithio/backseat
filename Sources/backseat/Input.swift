import AppKit
import CoreGraphics

/// Synthetic input delivered to one process (`CGEventPostToPid`) instead of
/// the system-wide event stream, so the real cursor and keyboard focus are
/// never touched.
enum Input {
    // MARK: Keyboard

    static func type(_ text: String, pid: pid_t) {
        for ch in text {
            switch ch {
            case "\n", "\r": key(code: 36, flags: [], pid: pid)
            case "\t": key(code: 48, flags: [], pid: pid)
            default:
                let units = Array(String(ch).utf16)
                for down in [true, false] {
                    guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
                    e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                    e.postToPid(pid)
                }
            }
            usleep(4_000)
        }
    }

    static func key(code: CGKeyCode, flags: CGEventFlags, pid: pid_t) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.postToPid(pid)
            // A real key stays down for a moment; some apps act on the release
            // only if they've seen the press first.
            if down { usleep(20_000) }
        }
    }

    /// Parses "cmd+shift+s", "return", "Escape" etc.
    static func parseCombo(_ combo: String) throws -> (CGKeyCode, CGEventFlags) {
        var flags: CGEventFlags = []
        var keyName: String?
        for part in combo.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd", "command", "⌘", "meta", "super": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default: keyName = part
            }
        }
        guard let keyName, let code = keyCodes[keyName] else {
            throw ToolError("unknown key in '\(combo)'. Use names like a, 1, return, tab, space, escape, delete, up, f5, with modifiers cmd/shift/opt/ctrl joined by +")
        }
        return (code, flags)
    }

    static let keyCodes: [String: CGKeyCode] = {
        var m: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
            "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
            "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
            "n": 45, "m": 46, ".": 47, "`": 50,
            "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
            "escape": 53, "esc": 53, "forwarddelete": 117, "home": 115, "end": 119,
            "pageup": 116, "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
        ]
        let f: [CGKeyCode] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (i, code) in f.enumerated() { m["f\(i + 1)"] = code }
        return m
    }()

    // MARK: Mouse

    // Pointer events go straight to the window's process (no WindowServer
    // routing, so no click-to-activate and no Space switch) and carry the
    // target window number, which is what makes AppKit deliver them to a
    // background, covered or off-screen window.
    //
    // Building them through NSEvent.mouseEvent(windowNumber:) is the only way
    // found to get a window-relative location AppKit honours: CGEvent's own
    // location setter discards it. The receiver reads the y it gets as
    // primaryScreenHeight - y, so that is what we pass.

    enum Button: String { case left, right, middle }

    private static var primaryScreenHeight: CGFloat { CGDisplayBounds(CGMainDisplayID()).height }

    private static func post(_ type: NSEvent.EventType, at point: CGPoint, window: WindowInfo,
                             clicks: Int = 1, pressure: Float = 0, button: Int64 = 0) {
        let local = NSPoint(x: point.x, y: primaryScreenHeight - point.y)
        guard let ns = NSEvent.mouseEvent(with: type, location: local, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: Int(window.id), context: nil, eventNumber: 0,
                                          clickCount: clicks, pressure: pressure),
              let e = ns.cgEvent else { return }
        if button > 1 { e.setIntegerValueField(.mouseEventButtonNumber, value: button) }
        e.postToPid(window.pid)
    }

    /// Clicks at a window-relative point inside `window`, delivered only to its owner.
    static func click(at point: CGPoint, window: WindowInfo, button: Button, count: Int) {
        let (down, up, number): (NSEvent.EventType, NSEvent.EventType, Int64) = switch button {
        case .left: (.leftMouseDown, .leftMouseUp, 0)
        case .right: (.rightMouseDown, .rightMouseUp, 1)
        case .middle: (.otherMouseDown, .otherMouseUp, 2)
        }
        for n in 1...max(1, count) {
            post(down, at: point, window: window, clicks: n, pressure: 1, button: number)
            usleep(8_000)
            post(up, at: point, window: window, clicks: n, button: number)
            usleep(8_000)
        }
    }

    static func drag(from a: CGPoint, to b: CGPoint, window: WindowInfo) {
        post(.leftMouseDown, at: a, window: window, pressure: 1)
        let steps = 12
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            post(.leftMouseDragged, at: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), window: window, pressure: 1)
            usleep(10_000)
        }
        post(.leftMouseUp, at: b, window: window)
    }

    /// There is no public NSEvent constructor for scroll events, so start from
    /// a windowed mouse-moved event (which carries the window-relative
    /// location) and turn it into a scroll-wheel event.
    static func scroll(at point: CGPoint, dx: Int32, dy: Int32, window: WindowInfo) {
        let local = NSPoint(x: point.x, y: primaryScreenHeight - point.y)
        guard let ns = NSEvent.mouseEvent(with: .mouseMoved, location: local, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: Int(window.id), context: nil, eventNumber: 0,
                                          clickCount: 0, pressure: 0),
              let e = ns.cgEvent else { return }
        e.type = .scrollWheel
        e.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(dy / 10))
        e.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(dx / 10))
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(dy))
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(dx))
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.postToPid(window.pid)
    }
}
