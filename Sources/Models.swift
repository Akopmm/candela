import Foundation

// Subset of Jellyfin's DTOs. Jellyfin's JSON is PascalCase, so the properties mirror it.

struct ItemsResponse: Decodable {
    let Items: [Item]
    let TotalRecordCount: Int?
}

struct Item: Decodable, Identifiable, Hashable {
    let Id: String
    let Name: String
    let `Type`: String?
    let ProductionYear: Int?
    let Overview: String?
    let RunTimeTicks: Int64?
    let CommunityRating: Double?
    let OfficialRating: String?
    let Genres: [String]?
    let ImageTags: [String: String]?
    let BackdropImageTags: [String]?
    let ParentBackdropItemId: String?
    let ParentBackdropImageTags: [String]?
    let ParentThumbItemId: String?
    let SeriesId: String?
    let SeriesName: String?
    let SeriesPrimaryImageTag: String?
    let SeasonId: String?
    let IndexNumber: Int?
    let ParentIndexNumber: Int?
    let UserData: UserData?
    let MediaSources: [MediaSource]?
    let MediaStreams: [MediaStream]?

    var id: String { Id }
    static func == (a: Item, b: Item) -> Bool { a.Id == b.Id }
    func hash(into h: inout Hasher) { h.combine(Id) }

    var isSeries: Bool { Type == "Series" }
    var isEpisode: Bool { Type == "Episode" }
    var resumeTicks: Int64 { UserData?.PlaybackPositionTicks ?? 0 }
    var progress: Double {
        guard let r = RunTimeTicks, r > 0 else { return 0 }
        return min(1, Double(resumeTicks) / Double(r))
    }
    var runtimeText: String? {
        guard let r = RunTimeTicks, r > 0 else { return nil }
        let m = Int(r / 600_000_000)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
    var episodeLabel: String? {
        guard isEpisode, let e = IndexNumber else { return nil }
        return "S\(ParentIndexNumber ?? 0) · E\(e)"
    }
}

struct UserData: Decodable {
    let PlaybackPositionTicks: Int64?
    let Played: Bool?
    let PlayedPercentage: Double?
    let IsFavorite: Bool?
}

struct MediaSource: Decodable {
    let Id: String
    let Container: String?
    let Size: Int64?
    let Bitrate: Int?
    let MediaStreams: [MediaStream]?
}

struct MediaStream: Decodable, Hashable {
    let Index: Int
    let `Type`: String
    let Codec: String?
    let Profile: String?
    let Language: String?
    let Title: String?
    let DisplayTitle: String?
    let Channels: Int?
    let IsDefault: Bool?
    let IsForced: Bool?
    let IsExternal: Bool?
    let Width: Int?
    let Height: Int?
    let VideoRangeType: String?
    let DvProfile: Int?
    let AudioSpatialFormat: String?
    let BitRate: Int?

    var isAudio: Bool { Type == "Audio" }
    var isSubtitle: Bool { Type == "Subtitle" }
    var isVideo: Bool { Type == "Video" }
}

struct UserDto: Decodable {
    let Id: String
    let Name: String
    let Configuration: UserConfiguration?
}

struct UserConfiguration: Decodable {
    let AudioLanguagePreference: String?
    let SubtitleLanguagePreference: String?
}

struct AuthResult: Decodable {
    let AccessToken: String
    let User: UserDto
}

struct QuickConnectState: Decodable {
    let Authenticated: Bool
    let Secret: String
    let Code: String
}

struct PublicInfo: Decodable {
    let ServerName: String?
    let Version: String?
    let Id: String?
}
