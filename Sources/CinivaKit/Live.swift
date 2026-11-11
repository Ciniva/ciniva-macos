import Foundation

public struct PluginPlay: Decodable, Hashable, Sendable {
    public let stream: String
    public let title: String?

    public init(stream: String, title: String? = nil) {
        self.stream = stream
        self.title = title
    }

    enum CodingKeys: String, CodingKey { case stream, title }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stream = try c.decode(JSONValue.self, forKey: .stream).stringValue ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title)
    }
}

public struct LiveChannel: Hashable, Sendable {
    public let stream: String
    public var title: String
    public var image: String?

    public init(stream: String, title: String, image: String? = nil) {
        self.stream = stream
        self.title = title
        self.image = image
    }

    public init(item: PluginListItem, play: PluginPlay) {
        self.init(stream: play.stream, title: play.title ?? item.title, image: item.image)
    }

    /// The channel list for a plugin list: every playable item, in order.
    public static func channels(in items: [PluginListItem]) -> [LiveChannel] {
        items.compactMap { item in
            guard let play = item.play, !play.stream.isEmpty else { return nil }
            return LiveChannel(item: item, play: play)
        }
    }
}

/// A live player's channel list and the position in it; zapping wraps around.
public struct LiveLineup: Hashable, Sendable {
    public let pluginId: String
    public private(set) var channels: [LiveChannel]
    public private(set) var index: Int

    public init(pluginId: String, current: LiveChannel, channels: [LiveChannel] = []) {
        self.pluginId = pluginId
        if let i = channels.firstIndex(where: { $0.stream == current.stream }) {
            self.channels = channels
            self.channels[i] = current
            index = i
        } else {
            self.channels = [current]
            index = 0
        }
    }

    public var current: LiveChannel { channels[index] }
    public var canZap: Bool { channels.count > 1 }

    public mutating func zap(_ step: Int) {
        guard canZap else { return }
        let n = channels.count
        index = ((index + step) % n + n) % n
    }

    public mutating func update(title: String?, image: String?) {
        if let title, !title.isEmpty { channels[index].title = title }
        if let image, !image.isEmpty { channels[index].image = image }
    }
}

public struct LiveStart: Decodable, Hashable, Sendable {
    public let session: String
    public let playlist: String
    public let title: String?
    public let image: String?
    public let plan: JSONValue?

    enum CodingKeys: String, CodingKey { case session, playlist, title, image, plan }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        session = try c.decode(JSONValue.self, forKey: .session).stringValue ?? ""
        playlist = try c.decode(String.self, forKey: .playlist)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        plan = try c.decodeIfPresent(JSONValue.self, forKey: .plan)
    }
}

public enum LivePolicy {
    public static let maxRestarts = 5

    /// Body for `POST /api/plugins/{id}/live/{stream}` from an mpv client: it decodes everything, so ask for a copy.
    public static let mpvRequest: [String: JSONValue] = [
        "video_copy": .string("h264,hevc,av1,vp9"),
        "audio_copy": .string("aac,ac3,eac3"),
        "max_height": .number(2160),
        "audio_channels": .number(2),
    ]

    /// Seconds to wait before restart number `attempt` (1-based), or nil once it's time to give up.
    public static func restartDelay(attempt: Int) -> Double? {
        guard attempt >= 1, attempt <= maxRestarts else { return nil }
        return Double(min(8, attempt))
    }
}

extension CinivaClient {
    public func startLive(plugin: String, stream: String, body: [String: JSONValue] = LivePolicy.mpvRequest) async throws -> LiveStart {
        let data = try await send("POST", "/plugins/\(plugin)/live/\(stream)", body: .object(body), timeout: 75)
        do {
            return try JSONDecoder().decode(LiveStart.self, from: data)
        } catch {
            throw CinivaError.invalidResponse
        }
    }

    /// The playlist URL with the session token in the query, for players that can't send headers.
    public func livePlaylistURL(_ playlist: String) -> URL {
        var path = playlist
        if path.hasPrefix("/api/") { path = String(path.dropFirst(4)) }
        return apiURL(path, withToken: true)
    }
}
