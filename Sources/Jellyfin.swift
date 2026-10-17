import Foundation
import Security
import SwiftUI

/// Talks to the Jellyfin server and holds the signed-in session.
@MainActor
final class Jellyfin: ObservableObject {
    static let shared = Jellyfin()

    enum State { case connecting, needsServer, loggedOut, ready }

    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    /// Server addresses in order of preference — typically the LAN address first and a remote one
    /// (reverse proxy, Tailscale, ...) second. The first one that answers is used.
    @Published var servers: [String] = UserDefaults.standard.stringArray(forKey: "servers") ?? []

    @Published var state: State = .connecting
    @Published var server: URL?
    @Published var user: UserDto?
    @Published var lastError: String?

    private(set) var token: String?
    let deviceId: String = {
        if let d = UserDefaults.standard.string(forKey: "deviceId") { return d }
        let d = UUID().uuidString
        UserDefaults.standard.set(d, forKey: "deviceId")
        return d
    }()

    var authorization: String {
        // Header values must be ASCII; Mac names often aren't (Cyrillic, curly apostrophes), so keep only the ASCII part.
        let raw = Host.current().localizedName ?? ""
        let ascii = String(raw.unicodeScalars.filter { $0.isASCII && $0 != "\"" }).trimmingCharacters(in: .whitespaces)
        let device = ascii.count >= 3 ? ascii : "Mac"
        var s = "MediaBrowser Client=\"Cinema\", Device=\"\(device)\", DeviceId=\"\(deviceId)\", Version=\"\(Self.version)\""
        if let t = token { s += ", Token=\"\(t)\"" }
        return s
    }

    // MARK: - Startup

    func bootstrap() async {
        guard !servers.isEmpty else { state = .needsServer; return }
        state = .connecting
        server = await pickServer()
        guard server != nil else {
            lastError = "Can't reach \(servers.joined(separator: " or "))."
            state = .needsServer
            return
        }
        if let t = Keychain.get("token") {
            token = t
            if let me: UserDto = try? await get("/Users/Me") {
                user = me
                state = .ready
                return
            }
            token = nil
            Keychain.delete("token")
        }
        state = .loggedOut
    }

    private func pickServer() async -> URL? {
        for c in servers {
            if let url = URL(string: c), await Self.probe(url) != nil { return url }
        }
        return nil
    }

    static func probe(_ url: URL) async -> PublicInfo? {
        var req = URLRequest(url: url.appendingPathComponent("System/Info/Public"))
        req.timeoutInterval = 3
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(PublicInfo.self, from: data)
    }

    /// "192.168.1.10" → "http://192.168.1.10:8096"; full URLs are kept as typed.
    static func normalize(_ s: String) -> String? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if !t.contains("://") { t = "http://" + t }
        while t.hasSuffix("/") { t.removeLast() }
        guard var c = URLComponents(string: t), c.host != nil else { return nil }
        if c.port == nil && c.scheme == "http" && (c.path.isEmpty) { c.port = 8096 }
        return c.string
    }

    /// Saves the addresses if at least one of them answers as a Jellyfin server.
    func setServers(_ input: [String]) async -> Bool {
        let list = input.compactMap(Self.normalize)
        guard !list.isEmpty else { lastError = "Enter a server address."; return false }
        for s in list {
            if let u = URL(string: s), await Self.probe(u) != nil {
                servers = list
                UserDefaults.standard.set(list, forKey: "servers")
                lastError = nil
                await bootstrap()
                return true
            }
        }
        lastError = "No Jellyfin server answered at \(list.joined(separator: " or "))."
        return false
    }

    func changeServer() {
        signOut()
        state = .needsServer
    }

    // MARK: - Sign in

    func signIn(username: String, password: String) async {
        do {
            let r: AuthResult = try await post("/Users/AuthenticateByName", body: ["Username": username, "Pw": password])
            finishSignIn(r)
        } catch {
            lastError = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    func startQuickConnect() async throws -> QuickConnectState {
        // Jellyfin answers 400 if this POST carries any body, even "{}".
        let data = try await perform(try request("/QuickConnect/Initiate", method: "POST", query: [:], body: nil))
        return try JSONDecoder().decode(QuickConnectState.self, from: data)
    }

    /// Polls until the code is approved in another Jellyfin client, then signs in.
    func waitForQuickConnect(_ qc: QuickConnectState) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let s: QuickConnectState = try? await get("/QuickConnect/Connect", query: ["secret": qc.Secret]) else { continue }
            if s.Authenticated {
                do {
                    let r: AuthResult = try await post("/Users/AuthenticateWithQuickConnect", body: ["Secret": qc.Secret])
                    finishSignIn(r)
                } catch {
                    lastError = "Quick Connect failed: \(error.localizedDescription)"
                }
                return
            }
        }
    }

    private func finishSignIn(_ r: AuthResult) {
        token = r.AccessToken
        user = r.User
        Keychain.set(r.AccessToken, "token")
        lastError = nil
        state = .ready
    }

    func signOut() {
        Task { try? await send("/Sessions/Logout", method: "POST") }
        token = nil
        user = nil
        Keychain.delete("token")
        state = .loggedOut
    }

    // MARK: - Library

    static let listFields = "ProductionYear,Overview,PrimaryImageAspectRatio,RunTimeTicks,ParentBackdropItemId,ParentBackdropImageTags"

    func resume() async -> [Item] {
        (try? await get("/UserItems/Resume", query: ["userId": uid, "limit": "20", "mediaTypes": "Video",
                                                       "fields": Self.listFields]) as ItemsResponse)?.Items ?? []
    }

    func nextUp() async -> [Item] {
        (try? await get("/Shows/NextUp", query: ["userId": uid, "limit": "20", "fields": Self.listFields]) as ItemsResponse)?.Items ?? []
    }

    func latest(_ type: String) async -> [Item] {
        (try? await get("/Items/Latest", query: ["userId": uid, "includeItemTypes": type, "limit": "24",
                                                   "fields": Self.listFields]) as [Item]) ?? []
    }

    func library(_ type: String, sortBy: String, ascending: Bool, unplayedOnly: Bool) async -> [Item] {
        var q = ["userId": uid, "includeItemTypes": type, "recursive": "true", "sortBy": sortBy,
                 "sortOrder": ascending ? "Ascending" : "Descending", "fields": Self.listFields]
        if unplayedOnly { q["isPlayed"] = "false" }
        return (try? await get("/Items", query: q) as ItemsResponse)?.Items ?? []
    }

    func search(_ term: String) async -> [Item] {
        (try? await get("/Items", query: ["userId": uid, "searchTerm": term, "recursive": "true", "limit": "60",
                                            "includeItemTypes": "Movie,Series,Episode", "fields": Self.listFields]) as ItemsResponse)?.Items ?? []
    }

    func item(_ id: String) async throws -> Item {
        try await get("/Items/\(id)", query: ["userId": uid, "fields": "MediaSources,MediaStreams,Overview,Genres"])
    }

    func seasons(_ seriesId: String) async -> [Item] {
        (try? await get("/Shows/\(seriesId)/Seasons", query: ["userId": uid]) as ItemsResponse)?.Items ?? []
    }

    func episodes(_ seriesId: String, seasonId: String) async -> [Item] {
        (try? await get("/Shows/\(seriesId)/Episodes", query: ["userId": uid, "seasonId": seasonId,
                                                                 "fields": "Overview,RunTimeTicks"]) as ItemsResponse)?.Items ?? []
    }

    func setPlayed(_ id: String, _ played: Bool) async {
        try? await send("/UserPlayedItems/\(id)", method: played ? "POST" : "DELETE", query: ["userId": uid])
    }

    // MARK: - URLs

    func imageURL(_ id: String, type: String = "Primary", tag: String? = nil, maxWidth: Int) -> URL? {
        guard let s = server else { return nil }
        var c = URLComponents(url: s.appendingPathComponent("Items/\(id)/Images/\(type)"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "maxWidth", value: "\(maxWidth)"), URLQueryItem(name: "quality", value: "90")]
        if let t = tag { c.queryItems?.append(URLQueryItem(name: "tag", value: t)) }
        return c.url
    }

    func posterURL(_ i: Item, width: Int = 400) -> URL? {
        if i.isEpisode, let sid = i.SeriesId { return imageURL(sid, tag: i.SeriesPrimaryImageTag, maxWidth: width) }
        return imageURL(i.Id, tag: i.ImageTags?["Primary"], maxWidth: width)
    }

    func backdropURL(_ i: Item, width: Int = 1920) -> URL? {
        if let t = i.BackdropImageTags?.first { return imageURL(i.Id, type: "Backdrop/0", tag: t, maxWidth: width) }
        if let p = i.ParentBackdropItemId, let t = i.ParentBackdropImageTags?.first {
            return imageURL(p, type: "Backdrop/0", tag: t, maxWidth: width)
        }
        return nil
    }

    /// Landscape art for Continue Watching cards: episode still, else the backdrop.
    func thumbURL(_ i: Item) -> URL? {
        if i.isEpisode, let t = i.ImageTags?["Primary"] { return imageURL(i.Id, tag: t, maxWidth: 640) }
        return backdropURL(i, width: 640) ?? posterURL(i)
    }

    func streamURL(itemId: String, mediaSourceId: String) -> URL? {
        guard let s = server else { return nil }
        var c = URLComponents(url: s.appendingPathComponent("Videos/\(itemId)/stream"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "static", value: "true"),
                        URLQueryItem(name: "mediaSourceId", value: mediaSourceId),
                        URLQueryItem(name: "deviceId", value: deviceId)]
        return c.url
    }

    // MARK: - HTTP

    private var uid: String { user?.Id ?? "" }

    private func request(_ path: String, method: String, query: [String: String], body: Data?) throws -> URLRequest {
        guard let s = server else { throw URLError(.badURL) }
        var c = URLComponents(url: s.appendingPathComponent(String(path.dropFirst())), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: c.url!)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        if let b = body {
            req.httpBody = b
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func perform(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw URLError(.userAuthenticationRequired) }
        guard (200..<300).contains(code) else { throw URLError(.badServerResponse) }
        return data
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let data = try await perform(try request(path, method: "GET", query: query, body: nil))
        return try JSONDecoder().decode(T.self, from: data)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let data = try await perform(try request(path, method: "POST", query: [:], body: try JSONEncoder().encode(body)))
        return try JSONDecoder().decode(T.self, from: data)
    }

    func send(_ path: String, method: String, query: [String: String] = [:], json: [String: Any]? = nil) async throws {
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        _ = try await perform(try request(path, method: method, query: query, body: body))
    }
}

/// The access token lives in the login keychain, not in plain preferences.
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "cinema"

    static func set(_ value: String, _ key: String) {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecValueData as String: Data(value.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}
