import Foundation

/// Jellyfin's LAN auto-discovery: broadcast "Who is JellyfinServer?" to UDP 7359 and collect the replies.
enum Discovery {
    struct Found: Decodable, Hashable {
        let Address: String
        let Id: String
        let Name: String
    }

    static func scan(timeout: TimeInterval = 2.0) async -> [Found] {
        await Task.detached { () -> [Found] in
            let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard fd >= 0 else { return [] }
            defer { close(fd) }
            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
            var tv = timeval(tv_sec: 0, tv_usec: 300_000)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(7359).bigEndian
            addr.sin_addr.s_addr = INADDR_BROADCAST
            let msg = Array("Who is JellyfinServer?".utf8)
            _ = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, msg, msg.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            var found = Set<Found>()
            let deadline = Date().addingTimeInterval(timeout)
            var buf = [UInt8](repeating: 0, count: 4096)
            while Date() < deadline {
                let n = recv(fd, &buf, buf.count, 0)
                if n > 0, let f = try? JSONDecoder().decode(Found.self, from: Data(buf[0..<n])) { found.insert(f) }
            }
            return found.sorted { $0.Name < $1.Name }
        }.value
    }
}
