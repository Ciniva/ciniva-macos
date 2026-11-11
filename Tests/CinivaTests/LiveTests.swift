import CinivaKit
import XCTest

final class LiveTests: XCTestCase {
    private let listJSON = """
    {
      "title": "Live TV",
      "blocks": [
        { "type": "list", "id": "channels", "items": [
          { "id": "1", "title": "Imedi", "image": "https://logos.example/imedi.png", "play": { "stream": "ge.imedi" } },
          { "id": "2", "title": "Settings", "link": { "page": "settings" } },
          { "id": "3", "title": "Rustavi 2", "play": { "stream": "ge-rustavi_2", "title": "Rustavi 2 HD" },
            "actions": [ { "label": "Watch", "play": { "stream": "ge-rustavi_2" } }, { "label": "Info", "navigate": { "page": "info" } } ] },
          { "id": "4", "title": "Broken", "play": { "stream": "" } },
          { "id": "5", "title": "Formula", "play": { "stream": "f1", "title": "F1" }, "link": { "page": "f1" } }
        ] }
      ]
    }
    """

    private func items() throws -> [PluginListItem] {
        let view = try CinivaClient.decodePluginView(Data(listJSON.utf8))
        guard case .list(_, let items, _) = view.blocks.first else {
            XCTFail("list")
            return []
        }
        return items
    }

    func testDecodesPlayOnItemsAndActions() throws {
        let items = try items()
        XCTAssertEqual(items[0].play, PluginPlay(stream: "ge.imedi"))
        XCTAssertNil(items[1].play)
        XCTAssertEqual(items[1].link?.page, "settings")
        XCTAssertEqual(items[2].play?.title, "Rustavi 2 HD")
        XCTAssertEqual(items[2].actions?[0].play?.stream, "ge-rustavi_2")
        XCTAssertNil(items[2].actions?[1].play)
        XCTAssertEqual(items[2].actions?[1].navigate?.page, "info")
        XCTAssertEqual(items[4].link?.page, "f1", "link survives next to play")
    }

    func testChannelListSkipsItemsWithoutAStream() throws {
        let channels = LiveChannel.channels(in: try items())
        XCTAssertEqual(channels.map(\.stream), ["ge.imedi", "ge-rustavi_2", "f1"])
        XCTAssertEqual(channels.map(\.title), ["Imedi", "Rustavi 2 HD", "F1"])
        XCTAssertEqual(channels[0].image, "https://logos.example/imedi.png")
        XCTAssertNil(channels[1].image)
    }

    func testLineupZapsAndWraps() throws {
        let channels = LiveChannel.channels(in: try items())
        var lineup = LiveLineup(pluginId: "iptv", current: channels[1], channels: channels)
        XCTAssertEqual(lineup.index, 1)
        XCTAssertTrue(lineup.canZap)
        lineup.zap(1)
        XCTAssertEqual(lineup.current.stream, "f1")
        lineup.zap(1)
        XCTAssertEqual(lineup.current.stream, "ge.imedi")
        lineup.zap(-1)
        XCTAssertEqual(lineup.current.stream, "f1")
        lineup.zap(-4)
        XCTAssertEqual(lineup.current.stream, "ge-rustavi_2")
    }

    func testLineupWithoutListCannotZap() {
        var lineup = LiveLineup(pluginId: "iptv", current: LiveChannel(stream: "a", title: "A"), channels: [])
        XCTAssertFalse(lineup.canZap)
        lineup.zap(1)
        XCTAssertEqual(lineup.current.stream, "a")

        let other = LiveLineup(pluginId: "iptv", current: LiveChannel(stream: "x", title: "X"), channels: [
            LiveChannel(stream: "a", title: "A"), LiveChannel(stream: "b", title: "B"),
        ])
        XCTAssertEqual(other.channels.map(\.stream), ["x"], "a channel missing from the list plays alone")
    }

    func testLineupTakesServerTitleAndImage() {
        var lineup = LiveLineup(pluginId: "iptv", current: LiveChannel(stream: "a", title: "A"), channels: [
            LiveChannel(stream: "a", title: "A", image: "old.png"), LiveChannel(stream: "b", title: "B"),
        ])
        lineup.update(title: "", image: nil)
        XCTAssertEqual(lineup.current.title, "A")
        lineup.update(title: "Channel A", image: "new.png")
        XCTAssertEqual(lineup.current, LiveChannel(stream: "a", title: "Channel A", image: "new.png"))
        XCTAssertEqual(lineup.channels[1].title, "B")
    }

    func testDecodesLiveStart() throws {
        let json = """
        { "session": "00ab12cd34ef5678", "playlist": "/api/live/00ab12cd34ef5678/index.m3u8",
          "plan": { "device": "Live (h264 copied)", "remux": true }, "live": true, "title": "Imedi", "image": null }
        """
        let start = try JSONDecoder().decode(LiveStart.self, from: Data(json.utf8))
        XCTAssertEqual(start.session, "00ab12cd34ef5678")
        XCTAssertEqual(start.title, "Imedi")
        XCTAssertNil(start.image)
        XCTAssertEqual(start.plan?["remux"], .bool(true))
    }

    func testPlaylistURLCarriesToken() throws {
        let client = CinivaClient(baseURL: try XCTUnwrap(URL(string: "http://host:8484")), token: "secret")
        let url = client.livePlaylistURL("/api/live/abc/index.m3u8")
        XCTAssertEqual(url.absoluteString, "http://host:8484/api/live/abc/index.m3u8?token=secret")
    }

    func testRequestAsksForCopiesAndRestartsBackOff() {
        XCTAssertEqual(LivePolicy.mpvRequest["video_copy"], .string("h264,hevc,av1,vp9"))
        XCTAssertEqual(LivePolicy.mpvRequest["audio_copy"], .string("aac,ac3,eac3"))
        XCTAssertEqual(LivePolicy.mpvRequest["max_height"], .number(2160))
        XCTAssertEqual(LivePolicy.mpvRequest["audio_channels"], .number(2))
        XCTAssertNil(LivePolicy.restartDelay(attempt: 0))
        XCTAssertEqual(LivePolicy.restartDelay(attempt: 1), 1)
        XCTAssertEqual(LivePolicy.restartDelay(attempt: 5), 5)
        XCTAssertNil(LivePolicy.restartDelay(attempt: 6))
    }
}
