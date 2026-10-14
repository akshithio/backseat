import AppKit
import ApplicationServices

/// Looks up which menu item a keyboard shortcut belongs to.
enum Menus {
    struct Item {
        let element: AXUIElement
        let path: String
    }

    /// The menu item whose shortcut is this key code + modifiers, if any.
    static func item(for code: CGKeyCode, flags: CGEventFlags, pid: pid_t) -> Item? {
        guard let bar = AX.attr(AX.app(pid), kAXMenuBarAttribute).map({ $0 as! AXUIElement }) else { return nil }
        let char = Input.keyCodes.first { $0.value == code && $0.key.count == 1 }?.key.uppercased()
        // kAXMenuItemCmdModifiers bits: shift 1, option 2, control 4, no-command 8.
        var want = 0
        if flags.contains(.maskShift) { want |= 1 }
        if flags.contains(.maskAlternate) { want |= 2 }
        if flags.contains(.maskControl) { want |= 4 }
        if !flags.contains(.maskCommand) { want |= 8 }

        func search(_ items: [AXUIElement], path: [String], depth: Int) -> Item? {
            for item in items {
                let title = AX.string(item, kAXTitleAttribute) ?? ""
                let mods = (AX.attr(item, kAXMenuItemCmdModifiersAttribute) as? Int) ?? 0
                var matches = false
                if let key = AX.attr(item, kAXMenuItemCmdCharAttribute) as? String, !key.isEmpty, let char {
                    matches = key.uppercased() == char
                } else if let vk = AX.attr(item, kAXMenuItemCmdVirtualKeyAttribute) as? Int {
                    matches = vk == Int(code)
                }
                if matches && mods == want { return Item(element: item, path: (path + [title]).joined(separator: " > ")) }
                if depth < 4, let submenu = AX.elements(item, kAXChildrenAttribute).first,
                   let found = search(AX.elements(submenu, kAXChildrenAttribute), path: path + [title], depth: depth + 1) {
                    return found
                }
            }
            return nil
        }
        return search(AX.elements(bar, kAXChildrenAttribute), path: [], depth: 0)
    }
}
