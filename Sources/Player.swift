import AppKit
import Foundation

extension Notification.Name {
    static let candelaPlaybackEnded = Notification.Name("candelaPlaybackEnded")
}

/// Track choice: remembers the last language picked, and within a language prefers the best-sounding track.
enum Tracks {
    static func audioScore(_ s: MediaStream) -> Int {
        let codec = (s.Codec ?? "").lowercased()
        let profile = (s.Profile ?? "").lowercased()
        let spatial = (s.AudioSpatialFormat ?? "").lowercased()
        var score = 0
        if spatial.contains("atmos") { score += 40 }
        if spatial.contains("dtsx") { score += 30 }
        switch codec {
        case "truehd": score += 35
        case "dts": score += profile.contains("ma") || profile.contains("hd") ? 33 : 22
        case "flac", "pcm_s24le", "pcm_s16le": score += 30
        case "eac3": score += 20
        case "ac3": score += 15
        case "aac": score += 10
        default: score += 5
        }
        return score + (s.Channels ?? 2)
    }

    static func defaultAudio(_ streams: [MediaStream], preferred: String?) -> MediaStream? {
        let audio = streams.filter { $0.isAudio && $0.IsExternal != true }
        let lang = UserDefaults.standard.string(forKey: "lastAudioLang") ?? preferred
        if let lang, !lang.isEmpty {
            let inLang = audio.filter { $0.Language == lang }
            if let best = inLang.max(by: { audioScore($0) < audioScore($1) }) { return best }
        }
        return audio.first { $0.IsDefault == true } ?? audio.first
    }

    static func defaultSubtitle(_ streams: [MediaStream], audio: MediaStream?) -> MediaStream? {
        let subs = streams.filter { $0.isSubtitle && $0.IsExternal != true }
        guard let lang = UserDefaults.standard.string(forKey: "lastSubLang"), !lang.isEmpty else { return nil }
        // Forced subtitles only translate foreign-language lines, so they go with the audio's language.
        return subs.first { $0.Language == lang && $0.IsForced != true } ?? subs.first { $0.Language == lang }
    }

    /// mpv numbers tracks per type from 1, in file order; Jellyfin uses one global index.
    static func mpvId(_ s: MediaStream, in streams: [MediaStream]) -> Int? {
        let same = streams.filter { $0.Type == s.Type && $0.IsExternal != true }.sorted { $0.Index < $1.Index }
        return same.firstIndex { $0.Index == s.Index }.map { $0 + 1 }
    }
}

@MainActor
final class MPVPlayer: ObservableObject {
    static let shared = MPVPlayer()

    @Published var nowPlaying: String?
    @Published var error: String?

    private var process: Process?
    private var ipc: MPVIPC?
    private var timer: Timer?
    private var position: Double = 0
    private var paused = false
    private var started = false
    private var current: (item: Item, sourceId: String, audio: Int?, sub: Int?)?

    /// Release builds carry their own mpv (Contents/MacOS/mpv + Contents/Frameworks); source builds use Homebrew's.
    static var bundledMPV: String? {
        guard let p = Bundle.main.path(forAuxiliaryExecutable: "mpv"), FileManager.default.isExecutableFile(atPath: p) else { return nil }
        return p
    }

    static var mpvPath: String? {
        bundledMPV ?? ["/opt/homebrew/bin/mpv", "/usr/local/bin/mpv"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var supportDir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Candela")
        try? FileManager.default.createDirectory(at: d.appendingPathComponent("mpv"), withIntermediateDirectories: true)
        return d
    }

    func play(_ item: Item, source: MediaSource, audio: MediaStream?, subtitle: MediaStream?, fromStart: Bool) {
        let api = Jellyfin.shared
        guard let mpv = Self.mpvPath else {
            error = "mpv isn't installed. In Terminal run:  brew install mpv"
            return
        }
        guard let url = api.streamURL(itemId: item.Id, mediaSourceId: source.Id) else { return }
        stopCurrent()

        let streams = source.MediaStreams ?? item.MediaStreams ?? []
        let sock = Self.supportDir.appendingPathComponent("mpv.sock").path
        try? FileManager.default.removeItem(atPath: sock)

        var title = item.Name
        if let s = item.SeriesName, let e = item.episodeLabel { title = "\(s) — \(e) — \(item.Name)" }

        var args = [
            "--config-dir=\(Self.supportDir.appendingPathComponent("mpv").path)",
            "--input-ipc-server=\(sock)",
            "--http-header-fields-append=Authorization: \(api.authorization)",
            "--force-media-title=\(title)",
            "--log-file=\(Self.supportDir.appendingPathComponent("mpv.log").path)",
            "--msg-level=all=info,vo=v",
        ]
        if let conf = Bundle.main.url(forResource: "candela", withExtension: "conf") {
            args.insert("--include=\(conf.path)", at: 0)
        }
        let start = fromStart ? 0 : Double(item.resumeTicks) / 10_000_000
        if start > 5 { args.append("--start=\(Int(start))") }
        if let a = audio, let id = Tracks.mpvId(a, in: streams) { args.append("--aid=\(id)") }
        if let s = subtitle, let id = Tracks.mpvId(s, in: streams) { args.append("--sid=\(id)") } else { args.append("--sid=no") }
        args.append(url.absoluteString)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: mpv)
        p.arguments = args
        if Self.bundledMPV != nil, let icd = Bundle.main.url(forResource: "MoltenVK_icd", withExtension: "json", subdirectory: "vulkan/icd.d") {
            // The Vulkan loader would otherwise look for MoltenVK in Homebrew's prefix.
            var env = ProcessInfo.processInfo.environment
            env["VK_DRIVER_FILES"] = icd.path
            env["VK_ICD_FILENAMES"] = icd.path
            p.environment = env
        }
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { _ in Task { @MainActor in MPVPlayer.shared.finished() } }
        do { try p.run() } catch {
            self.error = "Couldn't start mpv: \(error.localizedDescription)"
            return
        }
        process = p
        position = start
        paused = false
        started = false
        current = (item, source.Id, audio?.Index, subtitle?.Index)
        nowPlaying = title

        // mpv creates the socket a moment after launch.
        Task { [weak self] in
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if let c = MPVIPC(path: sock, onEvent: { ev in Task { @MainActor in self?.handle(ev) } }) {
                    self?.ipc = c
                    c.send(["command": ["observe_property", 1, "time-pos"]])
                    c.send(["command": ["observe_property", 2, "pause"]])
                    return
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in MPVPlayer.shared.report("/Sessions/Playing/Progress") }
        }
    }

    private func handle(_ ev: [String: Any]) {
        guard (ev["event"] as? String) == "property-change", let id = ev["id"] as? Int else { return }
        if id == 1, let t = ev["data"] as? Double {
            position = t
            if !started { started = true; report("/Sessions/Playing") }
        } else if id == 2, let p = ev["data"] as? Bool, p != paused {
            paused = p
            report("/Sessions/Playing/Progress")
        }
    }

    private func report(_ path: String) {
        guard let c = current else { return }
        var body: [String: Any] = ["ItemId": c.item.Id, "MediaSourceId": c.sourceId, "PlayMethod": "DirectPlay",
                                   "PositionTicks": Int64(position * 10_000_000), "IsPaused": paused, "CanSeek": true]
        if let a = c.audio { body["AudioStreamIndex"] = a }
        if let s = c.sub { body["SubtitleStreamIndex"] = s }
        Task { try? await Jellyfin.shared.send(path, method: "POST", json: body) }
    }

    private func finished() {
        if started { report("/Sessions/Playing/Stopped") }
        timer?.invalidate(); timer = nil
        ipc?.close(); ipc = nil
        process = nil
        current = nil
        nowPlaying = nil
        NSApp.activate(ignoringOtherApps: true)
        // Give Jellyfin a moment to store the position before the views reload.
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            NotificationCenter.default.post(name: .candelaPlaybackEnded, object: nil)
        }
    }

    private func stopCurrent() {
        if let p = process, p.isRunning { p.terminate() }
    }
}

/// Minimal client for mpv's JSON IPC over a Unix socket.
final class MPVIPC {
    private let fd: Int32
    private let handle: FileHandle
    private var buffer = Data()

    init?(path: String, onEvent: @escaping ([String: Any]) -> Void) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let ok = withUnsafeMutablePointer(to: &addr.sun_path) { ptr -> Bool in
            ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dst in
                guard path.utf8.count < 104 else { return false }
                strcpy(dst, path)
                return true
            }
        }
        let connected = ok && withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard connected else { Darwin.close(fd); return nil }
        self.fd = fd
        handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        handle.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard let self, !chunk.isEmpty else { h.readabilityHandler = nil; return }
            self.buffer.append(chunk)
            while let nl = self.buffer.firstIndex(of: 0x0A) {
                let line = self.buffer[..<nl]
                self.buffer.removeSubrange(...nl)
                if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { onEvent(obj) }
            }
        }
    }

    func send(_ obj: [String: Any]) {
        guard var d = try? JSONSerialization.data(withJSONObject: obj) else { return }
        d.append(0x0A)
        try? handle.write(contentsOf: d)
    }

    func close() {
        handle.readabilityHandler = nil
        try? handle.close()
    }
}
