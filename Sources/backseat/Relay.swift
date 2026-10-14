import AppKit

/// Lets an agent work in its own macOS session (a second user, logged in in the
/// background) where it has its own active app and keyboard focus, so commands
/// that need focus (Bold, Save, New Folder) run without ever touching the user's.
///
///     backseat listen <socket> --allow-uid <uid>   # in the agent's session
///     backseat connect <socket>                    # the MCP server the user's Claude runs
///
/// `listen` starts one backseat per connection, speaking MCP over the socket;
/// `connect` relays its stdin/stdout to that socket. The MCP stream itself is
/// passed through unchanged.
enum Relay {
    static func listen(_ path: String, allowUID: uid_t) -> Never {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { fail("socket: \(String(cString: strerror(errno)))") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else { fail("socket path too long") }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            _ = path.withCString { strncpy(raw.baseAddress!.assumingMemoryBound(to: CChar.self), $0, raw.count - 1) }
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { fail("bind \(path): \(String(cString: strerror(errno)))") }
        // Both users are in the staff group; only the allowed uid is served (checked per connection).
        chmod(path, 0o660)
        guard Darwin.listen(fd, 8) == 0 else { fail("listen: \(String(cString: strerror(errno)))") }
        log("listening on \(path) for uid \(allowUID)")

        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { continue }
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == allowUID else {
                log("refused a connection from uid \(uid)")
                close(client)
                continue
            }
            // The first line says what the client wants: "WATCH" for a live view of
            // this session's screen, anything else is the start of an MCP session.
            let first = readLine(client)
            if first == "WATCH" {
                Thread.detachNewThread { streamScreen(to: client) }
            } else {
                serve(client, firstLine: first)
            }
        }
    }

    private static func readLine(_ fd: Int32) -> String {
        var bytes: [UInt8] = []
        var b: UInt8 = 0
        while read(fd, &b, 1) == 1 {
            if b == 10 { break }
            bytes.append(b)
            if bytes.count > 1 << 20 { break }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Sends this session's screen as length-prefixed JPEG frames, ~4 a second,
    /// until the viewer goes away. Only the agent's session is ever captured.
    private static func streamScreen(to fd: Int32) {
        defer { close(fd) }
        while true {
            autoreleasepool {
                let bounds = CGDisplayBounds(CGMainDisplayID())
                if let img = Capture.screen(bounds, maxWidth: 1600), let data = img.jpeg(0.6) {
                    var len = UInt32(data.count).bigEndian
                    let ok = withUnsafeBytes(of: &len) { write(fd, $0.baseAddress, 4) } == 4
                        && data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) } == data.count
                    if !ok { return }
                }
            }
            if fcntl(fd, F_GETFD) == -1 { return }
            usleep(250_000)
        }
    }

    /// One backseat for this connection, its stdio wired to the socket.
    private static func serve(_ client: Int32, firstLine: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        var env = ProcessInfo.processInfo.environment
        // This session is the agent's own: nobody's focus to protect here.
        env["BACKSEAT_ALLOW_FOCUS_BORROW"] = "1"
        env["BACKSEAT_SESSION"] = "agent"
        proc.environment = env
        let toChild = Pipe(), fromChild = Pipe()
        proc.standardInput = toChild
        proc.standardOutput = fromChild
        do { try proc.run() } catch {
            log("couldn't start backseat: \(error)")
            close(client)
            return
        }
        let sock = FileHandle(fileDescriptor: client, closeOnDealloc: true)
        toChild.fileHandleForWriting.write(Data((firstLine + "\n").utf8))
        pump(from: sock, to: toChild.fileHandleForWriting) { proc.terminate() }
        pump(from: fromChild.fileHandleForReading, to: sock) { shutdown(client, SHUT_RDWR) }
    }

    /// A connected socket to `path`, or -1.
    static func open(_ path: String) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            _ = path.withCString { strncpy(raw.baseAddress!.assumingMemoryBound(to: CChar.self), $0, raw.count - 1) }
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if ok != 0 { close(fd); return -1 }
        return fd
    }

    static func connect(_ path: String) -> Never {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            _ = path.withCString { strncpy(raw.baseAddress!.assumingMemoryBound(to: CChar.self), $0, raw.count - 1) }
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else {
            fail("can't reach the agent's session at \(path) (\(String(cString: strerror(errno)))). Is the agent user logged in with backseat listening?")
        }
        let sock = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        pump(from: FileHandle.standardInput, to: sock) { shutdown(fd, SHUT_WR) }
        pump(from: sock, to: FileHandle.standardOutput) { exit(0) }
        dispatchMain()
    }

    /// Copies bytes until EOF on a background thread, then calls `done`.
    private static func pump(from src: FileHandle, to dst: FileHandle, done: @escaping @Sendable () -> Void) {
        Thread.detachNewThread {
            while true {
                let data = src.availableData
                if data.isEmpty { break }
                do { try dst.write(contentsOf: data) } catch { break }
            }
            done()
        }
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("backseat: \(s)\n".utf8)) }
    private static func fail(_ s: String) -> Never { log(s); exit(1) }
}
