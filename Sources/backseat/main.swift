import AppKit
import MCP

// Relay modes for running the agent in its own macOS session (see Relay.swift).
let argv = CommandLine.arguments
if argv.count >= 3, argv[1] == "connect" { Relay.connect(argv[2]) }
if argv.count >= 2, argv[1] == "watch" { Viewer.run(argv.count >= 3 ? argv[2] : "/Users/Shared/backseat/agent.sock") }
if argv.count >= 3, argv[1] == "listen" {
    let uid = argv.firstIndex(of: "--allow-uid").flatMap { $0 + 1 < argv.count ? uid_t(argv[$0 + 1]) : nil } ?? getuid()
    Relay.listen(argv[2], allowUID: uid)
}

let server = Server(
    name: "backseat",
    version: "0.1.0",
    instructions: """
    backseat drives macOS apps in the background while the user keeps using their Mac. \
    Nothing here moves the user's cursor or takes their keyboard focus. \
    Work in a window of your own: open one (select_menu_item New Window, or launch_app with a url), \
    keep its window_id, and act only there. Every window you open appears on the user's screen, so open one per task \
    and reuse it: in a browser, go to the next page with launch_app url + window_id, never a new window per page \
    (backseat allows \(Ownership.maxWindows) open per app). Windows you didn't open, and the one the user is in, are theirs; \
    backseat refuses to act in them unless you pass user_window: true because the user asked. \
    If your window starts showing something you didn't open, or the user moves into it, open a fresh one. \
    Loop: find_elements → click / set_value / type_text on element ids → read_text or get_ui_tree to check \
    (screenshots of windows the user can't see may be out of date). Use wait instead of sleeping. \
    Never repeat a send, submit or delete without first checking it didn't already happen. \
    Close every window you opened when done (list_windows marks them "yours"). Use coordinates only when an element isn't in the accessibility tree.
    """,
    capabilities: .init(tools: .init(listChanged: false))
)

// A background-only app: no Dock icon, never activates, but can show the
// highlight window and hear about other apps activating.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
_ = FocusGuard.shared

// First run: have macOS show its Accessibility and Screen Recording prompts
// for the app that launched backseat, instead of every tool failing quietly.
// Each prompt only appears once; after that these calls just return.
if !AXIsProcessTrusted() {
    _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
}
if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }

// The main run loop has to keep spinning so NSWorkspace sees app activation
// changes (FocusGuard relies on frontmostApplication being current).
Task {
    await server.withMethodHandler(ListTools.self) { _ in
        .init(tools: Tools.all)
    }
    await server.withMethodHandler(CallTool.self) { params in
        do {
            // A tool that never returns would leave the agent waiting forever.
            let output = try await withTimeout(seconds: 60) { try await Tools.call(params.name, Args(params.arguments)) }
            return .init(content: output.content, isError: false)
        } catch {
            return .init(content: [.text(text: "\(error)", annotations: nil, _meta: nil)], isError: true)
        }
    }
    do {
        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    } catch {
        FileHandle.standardError.write(Data("backseat: \(error)\n".utf8))
    }
    exit(0)
}
app.run()
