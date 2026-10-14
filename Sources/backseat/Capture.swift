import AppKit
import ScreenCaptureKit

extension CGImage {
    func jpeg(_ quality: Double) -> Data? {
        NSBitmapImageRep(cgImage: self).representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}

enum Capture {
    /// Captures one window, even when it is covered, on another Space, or off
    /// every display. The image is `scale` pixels per point, so at scale 1 a
    /// pixel (x, y) is the window-relative point (x, y) that `click` takes.
    static func window(_ id: CGWindowID, scale: Double, format: String) async throws -> (data: Data, mime: String, width: Int, height: Int) {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw ToolError("Screen Recording permission not granted to the app running backseat (System Settings → Privacy & Security → Screen Recording)")
        }
        let frame = Windows.frame(of: try Windows.get(id))
        let width = max(1, Int((frame.width * scale).rounded()))
        let height = max(1, Int((frame.height * scale).rounded()))

        // CoreGraphics first: ScreenCaptureKit makes macOS flash its screen-recording
        // indicator (a small icon at the top right of the user's screen) on every
        // capture, and CoreGraphics doesn't. It also reads covered windows and ones
        // on other Spaces or off every display.
        let image: CGImage
        if let legacy = legacy(id) {
            image = resized(legacy, width: width, height: height)
        } else {
            // ScreenCaptureKit can hang outright on some windows; never wait on it for long.
            do {
                image = try await withTimeout(seconds: 4) { try await screenCaptureKit(id, width: width, height: height) }
            } catch {
                throw ToolError("can't capture window \(id): \(error.localizedDescription)")
            }
        }

        let rep = NSBitmapImageRep(cgImage: image)
        let jpeg = format.lowercased() == "jpeg" || format.lowercased() == "jpg"
        guard let data = rep.representation(using: jpeg ? .jpeg : .png, properties: jpeg ? [.compressionFactor: 0.8] : [:]) else {
            throw ToolError("failed to encode image")
        }
        return (data, jpeg ? "image/jpeg" : "image/png", image.width, image.height)
    }

    /// The user's screen, cropped to exactly where window `id` is (plus the
    /// outline's width), composited as they see it. Never more than that region.
    static func asSeen(_ id: CGWindowID, scale: Double, format: String) throws -> (data: Data, mime: String, width: Int, height: Int) {
        guard CGPreflightScreenCaptureAccess() else {
            throw ToolError("Screen Recording permission not granted to the app running backseat")
        }
        let info = try Windows.get(id)
        guard Windows.visibleToUser(info) else {
            throw ToolError("window \(id) isn't visible on the user's screen right now (another Space, minimized, hidden or off every display); as_seen only shows what the user can see. Use a plain screenshot instead.")
        }
        let frame = Windows.frame(of: info).insetBy(dx: -2, dy: -2)  // room for the outline, nothing more
        let onScreenOnly: UInt32 = 1 << 0
        let boundsIgnoreFraming: UInt32 = 1 << 0, bestResolution: UInt32 = 1 << 3
        guard let img = createImage?(frame, onScreenOnly, kCGNullWindowID, boundsIgnoreFraming | bestResolution)?.takeRetainedValue() else {
            throw ToolError("couldn't capture the screen around window \(id)")
        }
        let width = max(1, Int((frame.width * scale).rounded())), height = max(1, Int((frame.height * scale).rounded()))
        let image = resized(img, width: width, height: height)
        let rep = NSBitmapImageRep(cgImage: image)
        let jpeg = format.lowercased().hasPrefix("j")
        guard let data = rep.representation(using: jpeg ? .jpeg : .png, properties: jpeg ? [.compressionFactor: 0.8] : [:]) else {
            throw ToolError("failed to encode image")
        }
        return (data, jpeg ? "image/jpeg" : "image/png", image.width, image.height)
    }

    /// A rectangle of this session's screen, scaled to at most `maxWidth` pixels wide.
    static func screen(_ rect: CGRect, maxWidth: Int) -> CGImage? {
        guard let img = createImage?(rect, 1 << 0, kCGNullWindowID, 1 << 0)?.takeRetainedValue() else { return nil }
        guard img.width > maxWidth else { return img }
        let h = Int(Double(img.height) * Double(maxWidth) / Double(img.width))
        return resized(img, width: maxWidth, height: h)
    }

    private static func screenCaptureKit(_ id: CGWindowID, width: Int, height: Int) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let w = content.windows.first(where: { $0.windowID == id }) else {
            throw ToolError("window \(id) is not capturable (minimized windows can't be captured)")
        }
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: w),
            configuration: config
        )
    }

    /// CGWindowListCreateImage is marked unavailable in the current SDK but
    /// still exported, so look it up at runtime.
    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private static let createImage: CreateImage? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let sym = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(sym, to: CreateImage.self)
    }()

    private static func legacy(_ id: CGWindowID) -> CGImage? {
        let includingWindow: UInt32 = 1 << 3
        let boundsIgnoreFraming: UInt32 = 1 << 0, bestResolution: UInt32 = 1 << 3
        return createImage?(.null, includingWindow, id, boundsIgnoreFraming | bestResolution)?.takeRetainedValue()
    }

    private static func resized(_ image: CGImage, width: Int, height: Int) -> CGImage {
        guard image.width != width || image.height != height,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }
}
