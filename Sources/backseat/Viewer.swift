import AppKit

/// `backseat watch <socket>`: a window, in the user's own session, showing the
/// agent's session live. View only: nothing here sends input anywhere. The user
/// opens it themselves, so it behaves like any app they launch.
enum Viewer {
    static func run(_ path: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "backseat · agent's screen"
        window.center()
        let image = NSImageView()
        image.imageScaling = .scaleProportionallyUpOrDown
        let status = NSTextField(labelWithString: "connecting to the agent's session…")
        status.textColor = .secondaryLabelColor
        status.alignment = .center
        let stack = NSView()
        for v in [image, status] {
            v.translatesAutoresizingMaskIntoConstraints = false
            stack.addSubview(v)
        }
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            image.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            image.topAnchor.constraint(equalTo: stack.topAnchor),
            image.bottomAnchor.constraint(equalTo: stack.bottomAnchor),
            status.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
            status.centerYAnchor.constraint(equalTo: stack.centerYAnchor),
        ])
        window.contentView = stack
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in exit(0) }

        Thread.detachNewThread {
            let fd = Relay.open(path)
            guard fd >= 0 else {
                DispatchQueue.main.async { status.stringValue = "The agent's session isn't reachable. Is the agent user logged in with backseat listening?" }
                return
            }
            _ = "WATCH\n".withCString { write(fd, $0, 6) }
            while true {
                var len: UInt32 = 0
                guard readFully(fd, &len, 4) else { break }
                let n = Int(UInt32(bigEndian: len))
                guard n > 0, n < 64 << 20 else { break }
                var data = Data(count: n)
                let ok = data.withUnsafeMutableBytes { readFully(fd, $0.baseAddress!, n) }
                guard ok, let img = NSImage(data: data) else { break }
                DispatchQueue.main.async {
                    status.isHidden = true
                    image.image = img
                }
            }
            DispatchQueue.main.async {
                status.isHidden = false
                status.stringValue = "The agent's session stopped sending its screen."
            }
        }
        app.run()
        exit(0)
    }

    private static func readFully(_ fd: Int32, _ buf: UnsafeMutableRawPointer, _ n: Int) -> Bool {
        var got = 0
        while got < n {
            let r = read(fd, buf + got, n - got)
            if r <= 0 { return false }
            got += r
        }
        return true
    }
}
