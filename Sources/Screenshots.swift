import AppKit
import SwiftUI

extension Notification.Name {
    /// userInfo: "section" (Section) or "item" (Item) — screenshot mode drives navigation through this.
    static let candelaNavigate = Notification.Name("candelaNavigate")
}

/// `CANDELA_SCREENSHOTS=/some/dir open -a Candela` walks through the main screens and saves PNGs of the
/// app's own window (no screen-recording permission needed), then quits. Used for the README images.
@MainActor
enum Screenshots {
    static let dir = ProcessInfo.processInfo.environment["CANDELA_SCREENSHOTS"]
    static var active: Bool { dir != nil }

    static func run(api: Jellyfin) async {
        guard let dir else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard await waitUntil({ api.state == .ready }, seconds: 30) else { print("not signed in"); exit(1) }
        // Showcase English tracks; put the user's own remembered choice back on the way out.
        let defaults = UserDefaults.standard
        let savedAudio = defaults.string(forKey: "lastAudioLang")
        defaults.set(ProcessInfo.processInfo.environment["CANDELA_SCREENSHOT_LANG"] ?? "eng", forKey: "lastAudioLang")
        atexit_b { if let a = savedAudio { defaults.set(a, forKey: "lastAudioLang") } else { defaults.removeObject(forKey: "lastAudioLang") }; defaults.synchronize() }
        resizeWindow(width: 1440, height: 900)

        await pause(8)
        capture("1-home", dir)

        go(["section": Section.movies])
        await pause(8)
        capture("2-movies", dir)

        let movies = await api.library("Movie", sortBy: "DateCreated", ascending: false, unplayedOnly: false)
        let wanted = ProcessInfo.processInfo.environment["CANDELA_SCREENSHOT_MOVIE"] ?? ""
        if let m = movies.first(where: { !wanted.isEmpty && $0.Name.localizedCaseInsensitiveContains(wanted) }) ?? movies.first {
            go(["item": m])
            await pause(8)
            capture("3-detail", dir)
        }

        let shows = await api.library("Series", sortBy: "DateCreated", ascending: false, unplayedOnly: false)
        if let s = shows.first {
            go(["section": Section.shows])
            await pause(2)
            go(["item": s])
            await pause(8)
            capture("4-series", dir)
        }
        exit(0)
    }

    private static func go(_ info: [String: Any]) {
        NotificationCenter.default.post(name: .candelaNavigate, object: nil, userInfo: info)
    }

    private static func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }

    private static func waitUntil(_ cond: () -> Bool, seconds: Double) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if cond() { return true }; await pause(0.25) }
        return cond()
    }

    private static var window: NSWindow? { NSApp.windows.first { $0.isVisible && $0.contentView != nil } }

    private static func resizeWindow(width: CGFloat, height: CGFloat) {
        guard let w = window else { return }
        w.setContentSize(NSSize(width: width, height: height))
        w.center()
        // Active window = coloured traffic lights and accent-coloured selection.
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    /// Renders the window's layer tree (content area, including the toolbar) at Retina scale.
    private static func capture(_ name: String, _ dir: String) {
        guard let w = window, let view = w.contentView?.superview ?? w.contentView, let layer = view.layer else { return }
        let scale = w.backingScaleFactor
        let size = view.bounds.size
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        layer.render(in: ctx)
        guard let img = ctx.makeImage() else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url)
        print("saved \(url.path) \(img.width)x\(img.height)")

        // Second method: AppKit's own drawing pass, which includes native controls and sidebar material.
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            let u2 = URL(fileURLWithPath: dir).appendingPathComponent("\(name)-appkit.png")
            try? rep.representation(using: .png, properties: [:])?.write(to: u2)
        }
    }
}
