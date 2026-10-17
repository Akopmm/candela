import SwiftUI

@main
struct CandelaApp: App {
    @StateObject private var api = Jellyfin.shared
    @StateObject private var player = MPVPlayer.shared

    var body: some Scene {
        WindowGroup("Candela") {
            RootView()
                .environmentObject(api)
                .environmentObject(player)
                .frame(minWidth: 1040, minHeight: 680)
                .preferredColorScheme(.dark)
        }
        .windowToolbarStyle(.unified)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

struct RootView: View {
    @EnvironmentObject var api: Jellyfin

    var body: some View {
        Group {
            switch api.state {
            case .connecting: ProgressView("Connecting to Jellyfin…")
            case .needsServer: ServerView()
            case .loggedOut: LoginView()
            case .ready: MainView()
            }
        }
        .task {
            await api.bootstrap()
            if Screenshots.active { await Screenshots.run(api: api) }
        }
    }
}

// MARK: - Server setup

struct ServerView: View {
    @EnvironmentObject var api: Jellyfin
    @State private var primary = ""
    @State private var remote = ""
    @State private var found: [Discovery.Found] = []
    @State private var scanning = false
    @State private var busy = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "play.rectangle.fill").font(.system(size: 64)).foregroundStyle(.tint)
            Text("Connect to your Jellyfin server").font(.largeTitle.bold())

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Servers on this network").font(.headline)
                        Spacer()
                        if scanning { ProgressView().controlSize(.small) }
                        Button("Scan") { Task { await scan() } }.disabled(scanning)
                    }
                    if found.isEmpty && !scanning {
                        Text("None found — enter the address below.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(found, id: \.Id) { f in
                        Button { primary = f.Address } label: {
                            HStack { Image(systemName: "server.rack"); Text(f.Name).bold(); Text(f.Address).foregroundStyle(.secondary) }
                        }.buttonStyle(.link)
                    }
                }.frame(width: 440).padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Address").font(.headline)
                    TextField("http://192.168.1.10:8096", text: $primary).textFieldStyle(.roundedBorder)
                    Text("Remote address (optional)").font(.headline).padding(.top, 4)
                    TextField("https://jellyfin.example.com", text: $remote).textFieldStyle(.roundedBorder)
                    Text("Used when the first address isn't reachable, e.g. away from home via a reverse proxy or Tailscale.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button(busy ? "Connecting…" : "Connect") { connect() }
                            .disabled(primary.isEmpty || busy).keyboardShortcut(.defaultAction)
                    }
                }.frame(width: 440).padding(8)
            }

            if let e = api.lastError { Text(e).foregroundStyle(.red).multilineTextAlignment(.center) }
        }
        .padding(40)
        .onAppear {
            if primary.isEmpty, let first = api.servers.first { primary = first }
            if remote.isEmpty, api.servers.count > 1 { remote = api.servers[1] }
        }
        .task { await scan() }
    }

    private func scan() async {
        scanning = true
        found = await Discovery.scan()
        if primary.isEmpty, let f = found.first { primary = f.Address }
        scanning = false
    }

    private func connect() {
        busy = true
        Task { _ = await api.setServers([primary, remote]); busy = false }
    }
}

// MARK: - Sign in

struct LoginView: View {
    @EnvironmentObject var api: Jellyfin
    @State private var qc: QuickConnectState?
    @State private var qcTask: Task<Void, Never>?
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "play.rectangle.fill").font(.system(size: 64)).foregroundStyle(.tint)
            Text("Sign in to Jellyfin").font(.largeTitle.bold())
            if let s = api.server { Text(s.absoluteString).foregroundStyle(.secondary) }

            GroupBox {
                VStack(spacing: 12) {
                    if let qc {
                        Text("Enter this code in Jellyfin → Settings → Quick Connect")
                            .foregroundStyle(.secondary)
                        Text(qc.Code).font(.system(size: 44, weight: .bold, design: .monospaced)).textSelection(.enabled)
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Use Quick Connect") { startQC() }.controlSize(.large)
                        Text("Approve with a code from Swiftfin, the Shield or the web app — no password needed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(width: 380).padding(8)
            }

            GroupBox {
                VStack(spacing: 10) {
                    TextField("Username", text: $username).textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
                        .onSubmit { signIn() }
                    Button(busy ? "Signing in…" : "Sign in") { signIn() }
                        .disabled(username.isEmpty || busy).keyboardShortcut(.defaultAction)
                }.frame(width: 380).padding(8)
            }

            if let e = api.lastError { Text(e).foregroundStyle(.red) }
            Button("Use a different server") { api.changeServer() }.buttonStyle(.link)
        }
        .padding(40)
        .onDisappear { qcTask?.cancel() }
    }

    private func startQC() {
        Task {
            do {
                let s = try await api.startQuickConnect()
                qc = s
                qcTask = Task { await api.waitForQuickConnect(s) }
            } catch {
                api.lastError = "Quick Connect is unavailable: \(error.localizedDescription)"
            }
        }
    }

    private func signIn() {
        busy = true
        Task { await api.signIn(username: username, password: password); busy = false }
    }
}

// MARK: - Shell

enum Section: Hashable {
    case home, movies, shows, search
    static let all: [Section] = [.home, .movies, .shows, .search]
    var title: String { ["Home", "Movies", "Shows", "Search"][Self.all.firstIndex(of: self)!] }
    var icon: String { ["house", "film", "tv", "magnifyingglass"][Self.all.firstIndex(of: self)!] }
}

struct ShotSidebar: View {
    @Binding var section: Section?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Section.all, id: \.self) { s in
                Label(s.title, systemImage: s.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(section == s ? Color.white : Color.primary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(section == s ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.155))
    }
}

struct MainView: View {
    @EnvironmentObject var api: Jellyfin
    @EnvironmentObject var player: MPVPlayer
    @State private var section: Section? = .home
    @State private var path = NavigationPath()

    var body: some View {
        NavigationSplitView {
            Group {
                if Screenshots.active {
                    // The native sidebar (NSTableView + vibrancy) can't be captured offscreen; draw the same rows.
                    ShotSidebar(section: $section)
                } else {
                    List(selection: $section) {
                        ForEach(Section.all, id: \.self) { s in Label(s.title, systemImage: s.icon).tag(s) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(190)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if let n = player.nowPlaying {
                        Label(n, systemImage: "play.fill").font(.caption).lineLimit(2).foregroundStyle(.tint)
                    }
                    HStack {
                        Text(Screenshots.active ? "" : (api.user?.Name ?? "")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            Text(api.server?.absoluteString ?? "")
                            Button("Change server…") { api.changeServer() }
                            Button("Sign out") { api.signOut() }
                        } label: { Image(systemName: "person.crop.circle") }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                }.padding(12)
            }
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    switch section ?? .home {
                    case .home: HomeView()
                    case .movies: LibraryView(type: "Movie", title: "Movies")
                    case .shows: LibraryView(type: "Series", title: "Shows")
                    case .search: SearchView()
                    }
                }
                .navigationDestination(for: Item.self) { item in
                    if item.isSeries { SeriesView(series: item) } else { DetailView(itemId: item.Id) }
                }
            }
        }
        .onChange(of: section) { _, _ in path = NavigationPath() }
        .onReceive(NotificationCenter.default.publisher(for: .candelaNavigate)) { n in
            if let s = n.userInfo?["section"] as? Section { section = s }
            if let i = n.userInfo?["item"] as? Item { path.append(i) }
        }
        .alert("Playback", isPresented: Binding(get: { player.error != nil }, set: { if !$0 { player.error = nil } })) {
            Button("OK") { player.error = nil }
        } message: { Text(player.error ?? "") }
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var api: Jellyfin
    @State private var resume: [Item] = []
    @State private var nextUp: [Item] = []
    @State private var movies: [Item] = []
    @State private var shows: [Item] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if !resume.isEmpty { Shelf(title: "Continue Watching") { ForEach(resume) { WideCard(item: $0) } } }
                if !nextUp.isEmpty { Shelf(title: "Next Up") { ForEach(nextUp) { WideCard(item: $0) } } }
                if !movies.isEmpty { Shelf(title: "Recently Added Movies") { ForEach(movies) { PosterCard(item: $0) } } }
                if !shows.isEmpty { Shelf(title: "Recently Added Shows") { ForEach(shows) { PosterCard(item: $0) } } }
            }.padding(24)
        }
        .navigationTitle("Home")
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .candelaPlaybackEnded)) { _ in Task { await load() } }
    }

    private func load() async {
        async let r = api.resume()
        async let n = api.nextUp()
        async let m = api.latest("Movie")
        async let s = api.latest("Series")
        (resume, nextUp, movies, shows) = await (r, n, m, s)
    }
}

struct Shelf<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) { content }.padding(.bottom, 6)
            }
        }
    }
}

// MARK: - Cards

struct RemoteImage: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            if let img = phase.image { img.resizable().scaledToFill() }
            else { Rectangle().fill(.quaternary) }
        }
    }
}

struct PosterCard: View {
    @EnvironmentObject var api: Jellyfin
    let item: Item
    var width: CGFloat = 150

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 6) {
                RemoteImage(url: api.posterURL(item))
                    .frame(width: width, height: width * 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        if item.UserData?.Played == true {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .green).padding(6)
                        }
                    }
                    .overlay(alignment: .bottom) { ProgressLine(value: item.progress).padding(6) }
                Text(item.Name).font(.callout.weight(.medium)).lineLimit(1)
                Text(item.ProductionYear.map(String.init) ?? " ").font(.caption).foregroundStyle(.secondary)
            }.frame(width: width)
        }.buttonStyle(.plain)
    }
}

struct WideCard: View {
    @EnvironmentObject var api: Jellyfin
    let item: Item

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 6) {
                RemoteImage(url: api.thumbURL(item))
                    .frame(width: 280, height: 158)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .bottom) { ProgressLine(value: item.progress).padding(8) }
                Text(item.SeriesName ?? item.Name).font(.callout.weight(.medium)).lineLimit(1)
                Text(item.isEpisode ? "\(item.episodeLabel ?? "") · \(item.Name)" : (item.ProductionYear.map(String.init) ?? " "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(width: 280)
        }.buttonStyle(.plain)
    }
}

struct ProgressLine: View {
    let value: Double
    var body: some View {
        if value > 0.01 && value < 0.99 {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.55))
                    Capsule().fill(Color.accentColor).frame(width: g.size.width * value)
                }
            }.frame(height: 4)
        }
    }
}

// MARK: - Library & search

struct LibraryView: View {
    @EnvironmentObject var api: Jellyfin
    let type: String
    let title: String
    @AppStorage("sortBy") private var sortBy = "SortName"
    @AppStorage("unplayedOnly") private var unplayedOnly = false
    @State private var items: [Item] = []
    @State private var loading = true

    private let sorts = [("SortName", "Title"), ("DateCreated", "Date added"), ("ProductionYear", "Year"),
                         ("CommunityRating", "Rating")]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 20)], spacing: 24) {
                ForEach(items) { PosterCard(item: $0) }
            }.padding(24)
            if loading { ProgressView().padding() }
        }
        .navigationTitle("\(title) (\(items.count))")
        .toolbar {
            Toggle(isOn: $unplayedOnly) { Label("Unwatched", systemImage: "eye.slash") }
            Menu {
                Picker("Sort", selection: $sortBy) { ForEach(sorts, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.inline)
            } label: {
                Label("Sort: \(sorts.first { $0.0 == sortBy }?.1 ?? "Title")", systemImage: "arrow.up.arrow.down")
                    .labelStyle(.titleAndIcon)
            }
        }
        .task(id: "\(type)\(sortBy)\(unplayedOnly)") { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .candelaPlaybackEnded)) { _ in Task { await load() } }
    }

    private func load() async {
        loading = true
        items = await api.library(type, sortBy: sortBy, ascending: sortBy == "SortName", unplayedOnly: unplayedOnly)
        loading = false
    }
}

struct SearchView: View {
    @EnvironmentObject var api: Jellyfin
    @State private var term = ""
    @State private var results: [Item] = []

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 20)], spacing: 24) {
                ForEach(results) { PosterCard(item: $0) }
            }.padding(24)
            if !term.isEmpty && results.isEmpty { Text("No results").foregroundStyle(.secondary).padding(40) }
        }
        .navigationTitle("Search")
        .searchable(text: $term, placement: .toolbar, prompt: "Films, shows, episodes")
        .task(id: term) {
            guard term.count >= 2 else { results = []; return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            results = await api.search(term)
        }
    }
}

// MARK: - Detail

struct DetailView: View {
    @EnvironmentObject var api: Jellyfin
    @EnvironmentObject var player: MPVPlayer
    let itemId: String
    @State private var item: Item?
    @State private var audio: Int?
    @State private var sub: Int = -1
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            if let item, let source = item.MediaSources?.first {
                let streams = source.MediaStreams ?? item.MediaStreams ?? []
                VStack(alignment: .leading, spacing: 0) {
                    header(item)
                    VStack(alignment: .leading, spacing: 18) {
                        Badges(streams: streams, source: source)
                        controls(item, source: source, streams: streams)
                        if let o = item.Overview { Text(o).font(.body).lineSpacing(3).frame(maxWidth: 820, alignment: .leading) }
                        if let g = item.Genres, !g.isEmpty { Text(g.joined(separator: " · ")).foregroundStyle(.secondary) }
                    }.padding(28)
                }
            } else if let loadError {
                Text(loadError).foregroundStyle(.red).padding(40)
            } else {
                ProgressView().padding(80)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(item?.SeriesName ?? item?.Name ?? "")
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .candelaPlaybackEnded)) { _ in Task { await load() } }
    }

    private func header(_ item: Item) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: api.backdropURL(item) ?? api.posterURL(item, width: 1200))
                .frame(height: 420).frame(maxWidth: .infinity).clipped()
            LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                if let s = item.SeriesName { Text(s).font(.title3).foregroundStyle(.secondary) }
                Text(item.Name).font(.system(size: 40, weight: .bold))
                Text(meta(item)).foregroundStyle(.secondary)
            }.padding(28)
        }
    }

    private func meta(_ i: Item) -> String {
        var parts: [String] = []
        if let e = i.episodeLabel { parts.append(e) }
        if let y = i.ProductionYear { parts.append(String(y)) }
        if let r = i.runtimeText { parts.append(r) }
        if let o = i.OfficialRating { parts.append(o) }
        if let c = i.CommunityRating { parts.append(String(format: "★ %.1f", c)) }
        return parts.joined(separator: "   ")
    }

    @ViewBuilder
    private func controls(_ item: Item, source: MediaSource, streams: [MediaStream]) -> some View {
        let audios = streams.filter { $0.isAudio && $0.IsExternal != true }
        let subs = streams.filter { $0.isSubtitle && $0.IsExternal != true }
        HStack(spacing: 12) {
            if item.resumeTicks > 0 {
                Button { start(item, source, streams, fromStart: false) } label: {
                    Label("Resume \(timeText(item.resumeTicks))", systemImage: "play.fill").frame(minWidth: 150)
                }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                Button { start(item, source, streams, fromStart: true) } label: {
                    Label("From start", systemImage: "backward.end.fill")
                }.controlSize(.large)
            } else {
                Button { start(item, source, streams, fromStart: true) } label: {
                    Label("Play", systemImage: "play.fill").frame(minWidth: 120)
                }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
            Button {
                Task { await api.setPlayed(item.Id, !(item.UserData?.Played ?? false)); await load() }
            } label: {
                Label(item.UserData?.Played == true ? "Watched" : "Mark watched",
                      systemImage: item.UserData?.Played == true ? "checkmark.circle.fill" : "checkmark.circle")
            }.controlSize(.large)
        }
        HStack(spacing: 16) {
            if !audios.isEmpty {
                Picker("Audio", selection: Binding(get: { audio ?? audios.first!.Index }, set: { audio = $0 })) {
                    ForEach(audios, id: \.Index) { Text(label($0)).tag($0.Index) }
                }.frame(maxWidth: 460)
            }
            Picker("Subtitles", selection: $sub) {
                Text("Off").tag(-1)
                ForEach(subs, id: \.Index) { Text(label($0)).tag($0.Index) }
            }.frame(maxWidth: 360)
        }
    }

    private func label(_ s: MediaStream) -> String {
        var t = s.DisplayTitle ?? s.Title ?? s.Codec ?? "Track \(s.Index)"
        if let title = s.Title, !title.isEmpty, !(s.DisplayTitle ?? "").contains(title) { t += " — \(title)" }
        if s.IsForced == true, !t.lowercased().contains("forced") { t += " (forced)" }
        return t
    }

    private func start(_ item: Item, _ source: MediaSource, _ streams: [MediaStream], fromStart: Bool) {
        let a = streams.first { $0.Index == audio }
        let s = streams.first { $0.Index == sub }
        // Remember the languages so the next film starts with the same choice.
        if let l = a?.Language { UserDefaults.standard.set(l, forKey: "lastAudioLang") }
        UserDefaults.standard.set(s?.Language ?? "", forKey: "lastSubLang")
        player.play(item, source: source, audio: a, subtitle: s, fromStart: fromStart)
    }

    private func timeText(_ ticks: Int64) -> String {
        let s = Int(ticks / 10_000_000)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    private func load() async {
        do {
            let i = try await api.item(itemId)
            item = i
            let streams = i.MediaSources?.first?.MediaStreams ?? i.MediaStreams ?? []
            if audio == nil {
                audio = Tracks.defaultAudio(streams, preferred: api.user?.Configuration?.AudioLanguagePreference)?.Index
                let a = streams.first { $0.Index == audio }
                sub = Tracks.defaultSubtitle(streams, audio: a)?.Index ?? -1
            }
        } catch {
            loadError = "Couldn't load this item: \(error.localizedDescription)"
        }
    }
}

struct Badges: View {
    let streams: [MediaStream]
    let source: MediaSource

    var body: some View {
        let v = streams.first { $0.isVideo }
        HStack(spacing: 8) {
            if let v {
                if let w = v.Width { Badge(text: w >= 3000 ? "4K" : (w >= 1800 ? "1080p" : (w >= 1200 ? "720p" : "SD"))) }
                switch v.VideoRangeType ?? "" {
                case let r where r.hasPrefix("DOVI"):
                    Badge(text: "Dolby Vision\(v.DvProfile.map { " \($0)" } ?? "")", strong: true)
                case "HDR10Plus": Badge(text: "HDR10+", strong: true)
                case "HDR10": Badge(text: "HDR10", strong: true)
                case "HLG": Badge(text: "HLG")
                default: Badge(text: "SDR")
                }
                if let c = v.Codec { Badge(text: c.uppercased()) }
            }
            if streams.contains(where: { ($0.AudioSpatialFormat ?? "").lowercased().contains("atmos") }) { Badge(text: "Atmos", strong: true) }
            if streams.contains(where: { $0.Codec == "truehd" }) { Badge(text: "TrueHD") }
            if streams.contains(where: { $0.Codec == "dts" && (($0.Profile ?? "").contains("MA") || ($0.AudioSpatialFormat ?? "") == "DTSX") }) {
                Badge(text: "DTS-HD MA")
            }
            if let b = source.Bitrate { Badge(text: "\(b / 1_000_000) Mb/s") }
            if let s = source.Size { Badge(text: String(format: "%.0f GB", Double(s) / 1e9)) }
        }
    }
}

struct Badge: View {
    let text: String
    var strong = false
    var body: some View {
        Text(text).font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(strong ? AnyShapeStyle(Color.accentColor.opacity(0.85)) : AnyShapeStyle(.quaternary),
                        in: RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Series

struct SeriesView: View {
    @EnvironmentObject var api: Jellyfin
    let series: Item
    @State private var seasons: [Item] = []
    @State private var season: String?
    @State private var episodes: [Item] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: api.backdropURL(series)).frame(height: 320).frame(maxWidth: .infinity).clipped()
                    LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)], startPoint: .center, endPoint: .bottom)
                    Text(series.Name).font(.system(size: 40, weight: .bold)).padding(28)
                }
                VStack(alignment: .leading, spacing: 16) {
                    if let o = series.Overview { Text(o).frame(maxWidth: 820, alignment: .leading).foregroundStyle(.secondary) }
                    if seasons.count > 1 {
                        Picker("Season", selection: $season) {
                            ForEach(seasons) { Text($0.Name).tag(Optional($0.Id)) }
                        }.pickerStyle(.segmented).frame(maxWidth: 700)
                    }
                    ForEach(episodes) { ep in
                        NavigationLink(value: ep) {
                            HStack(alignment: .top, spacing: 16) {
                                RemoteImage(url: api.imageURL(ep.Id, tag: ep.ImageTags?["Primary"], maxWidth: 480))
                                    .frame(width: 240, height: 135).clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(alignment: .bottom) { ProgressLine(value: ep.progress).padding(6) }
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("\(ep.IndexNumber.map { "\($0). " } ?? "")\(ep.Name)").font(.headline)
                                        if ep.UserData?.Played == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                    }
                                    if let r = ep.runtimeText { Text(r).font(.caption).foregroundStyle(.secondary) }
                                    if let o = ep.Overview { Text(o).font(.callout).foregroundStyle(.secondary).lineLimit(3) }
                                }
                                Spacer()
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 28).padding(.bottom, 28)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(series.Name)
        .task {
            seasons = await api.seasons(series.Id)
            if season == nil { season = seasons.first(where: { ($0.UserData?.Played ?? false) == false })?.Id ?? seasons.first?.Id }
        }
        .task(id: season) { await loadEpisodes() }
        .onReceive(NotificationCenter.default.publisher(for: .candelaPlaybackEnded)) { _ in Task { await loadEpisodes() } }
    }

    private func loadEpisodes() async {
        guard let s = season else { return }
        episodes = await api.episodes(series.Id, seasonId: s)
    }
}
