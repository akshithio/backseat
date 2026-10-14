import AppKit
import QuartzCore

/// A green outline around the window backseat is working in, so the user can
/// see where the agent is without anything taking their focus.
///
/// The outline is its own click-through window, ordered directly above the
/// target window rather than above everything: if the user's own windows
/// cover the target, they cover the outline too. It fades out a couple of
/// seconds after the agent's last action, and it is never shown for windows
/// that aren't on the user's screen (other Spaces, off screen).
final class Overlay: @unchecked Sendable {
    static let shared = Overlay()

    private var panel: NSPanel?
    private var target: CGWindowID?
    private var hideAt = Date.distantPast
    private var timer: Timer?
    private let linger: TimeInterval = 2.5

    var enabled = ProcessInfo.processInfo.environment["BACKSEAT_HIGHLIGHT"] != "0"

    /// The target's accessibility element, looked up once per target. Its frame
    /// is exact; the CoreGraphics one lags during moves and resizes and can be
    /// caught mid-animation, which left the outline off the window's edges.
    private var axWindow: AXUIElement?
    private var radius: CGFloat = 16

    /// Outline `window` (called from any thread).
    func highlight(_ window: CGWindowID?) {
        guard enabled, let window else { return }
        DispatchQueue.main.async { [self] in
            if target != window {
                target = window
                axWindow = nil
                if let info = try? Windows.get(window), let w = AX.window(id: window, pid: info.pid) {
                    // Never let a busy app stall the outline (and backseat's main thread).
                    AXUIElementSetMessagingTimeout(w, 0.1)
                    axWindow = w
                    radius = Self.cornerRadius(of: w)
                }
            }
            hideAt = Date().addingTimeInterval(linger)
            update()
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.update() }
            }
        }
    }

    /// Outline the window containing an element.
    func highlight(element: AXUIElement) {
        highlight(AX.containingWindow(element).flatMap(AX.windowID))
    }

    /// macOS 26 rounds windows with a toolbar much more than plain titled ones.
    private static func cornerRadius(of window: AXUIElement) -> CGFloat {
        let hasToolbar = AX.elements(window, kAXChildrenAttribute).contains {
            AX.string($0, kAXRoleAttribute) == "AXToolbar"
        }
        if #available(macOS 26, *) { return hasToolbar ? 26 : 16 }
        return 10
    }

    private func update() {
        // Only outline what the user can actually see: never an empty box where
        // a minimized, hidden, see-through or other-Space window would be.
        guard let target, Date() < hideAt, let info = try? Windows.get(target), Windows.visibleToUser(info),
              (axWindow.map { AX.attr($0, kAXMinimizedAttribute) as? Bool } ?? false) != true else {
            hide()
            return
        }
        let panel = self.panel ?? makePanel()
        let f = axWindow.flatMap(AX.frame) ?? info.frame
        // AX/CG frames are top-left origin; AppKit's are bottom-left.
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        // The stroke straddles the window's edge, so its corners follow the window's.
        let w = width
        let rect = NSRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height).insetBy(dx: -w / 2, dy: -w / 2)
        if panel.frame != rect { panel.setFrame(rect, display: true) }
        if let layer = panel.contentView?.layer, layer.cornerRadius != radius + w / 2 {
            layer.cornerRadius = radius + w / 2
        }
        let remaining = hideAt.timeIntervalSinceNow
        panel.alphaValue = remaining < 0.5 ? max(0, remaining / 0.5) : 1
        // Same level as the target, or ordering above it can't work.
        let level = NSWindow.Level(rawValue: info.layer)
        if panel.level != level { panel.level = level }
        panel.order(.above, relativeTo: Int(target))
    }

    private let width: CGFloat = 3

    private func hide() {
        timer?.invalidate()
        timer = nil
        target = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        // Captures of a single window never include it (it's a separate window);
        // as_seen captures of the screen region do, so the agent sees what the user sees.
        p.sharingType = .readOnly
        p.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.borderColor = NSColor.systemGreen.cgColor
        view.layer?.borderWidth = width
        view.layer?.cornerCurve = .continuous
        p.contentView = view
        panel = p
        return p
    }
}
