import CinivaKit
import SwiftUI

struct ChannelLogo: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(4)
            } else {
                Image(systemName: "tv")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = await ImageCache.shared.load(url)
        }
    }
}

struct LivePlayerContainer: View {
    @Environment(AppModel.self) private var model
    @State private var controller: PlayerController
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    init(request: PlaybackRequest, client: CinivaClient?) {
        _controller = State(initialValue: PlayerController(request: request, client: client))
    }

    private var showControls: Bool {
        controlsVisible || controller.isPaused || controller.errorMessage != nil
    }

    var body: some View {
        ZStack {
            EngineHost(view: controller.engineView)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { toggleFullScreen() }
                .onTapGesture { controller.togglePause() }

            if controller.isBuffering && controller.errorMessage == nil {
                ProgressView().controlSize(.large).tint(.white)
            }

            if let error = controller.errorMessage {
                errorCard(error)
            }

            if showControls {
                controls.transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear {
            focused = true
            controller.onClose = { close() }
            controller.onUnauthorized = { model.sessionExpired() }
            Task { await controller.start() }
            bumpControls()
        }
        .onDisappear {
            controller.stop()
            hideTask?.cancel()
            NSCursor.setHiddenUntilMouseMoves(false)
        }
        .onContinuousHover { phase in
            if case .active = phase { bumpControls() }
        }
        .onKeyPress(.space) { controller.togglePause(); bumpControls(); return .handled }
        .onKeyPress(.upArrow) { zap(1) }
        .onKeyPress(.downArrow) { zap(-1) }
        .onKeyPress(.pageUp) { zap(1) }
        .onKeyPress(.pageDown) { zap(-1) }
        .onKeyPress(.escape) {
            if isFullScreen { toggleFullScreen() } else { close() }
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "fmk")) { press in
            switch press.characters {
            case "f": toggleFullScreen()
            case "m": controller.setVolume(controller.volume > 0 ? 0 : 100)
            case "k": controller.togglePause()
            default: return .ignored
            }
            bumpControls()
            return .handled
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
    }

    private func zap(_ step: Int) -> KeyPress.Result {
        guard controller.lineup?.canZap == true else { return .ignored }
        controller.zap(step)
        bumpControls()
        return .handled
    }

    private var playerWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    private var isFullScreen: Bool {
        playerWindow?.styleMask.contains(.fullScreen) == true
    }

    private func toggleFullScreen() {
        playerWindow?.toggleFullScreen(nil)
    }

    private func close() {
        if isFullScreen { toggleFullScreen() }
        model.closePlayer()
    }

    private func bumpControls() {
        controlsVisible = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            controlsVisible = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func errorCard(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle)
            Text("Couldn't play \(controller.title)").font(.headline)
            Text(error).multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack {
                Button("Try Again") { controller.retryLive() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                Button("Close") { close() }
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: 460)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .padding()
    }

    private var logoURL: URL? {
        model.client?.imageURL(controller.lineup?.current.image, size: "w185")
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 14) {
            Button { close() } label: {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Back (Esc)")
            ChannelLogo(url: logoURL)
                .frame(width: 72, height: 48)
                .environment(\.colorScheme, .dark)
            VStack(alignment: .leading, spacing: 4) {
                Text(controller.title).font(.title2.weight(.semibold)).lineLimit(1)
                LiveBadge()
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .padding(.bottom, 40)
        .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var bottomBar: some View {
        HStack(spacing: 18) {
            let canZap = controller.lineup?.canZap == true
            Button { controller.zap(-1) } label: { Image(systemName: "chevron.down") }
                .disabled(!canZap)
                .help("Channel down: previous in the list (↓)")
            Button { controller.togglePause() } label: {
                Image(systemName: controller.isPaused ? "play.fill" : "pause.fill").font(.title)
            }
            .help("Play/Pause (Space)")
            Button { controller.zap(1) } label: { Image(systemName: "chevron.up") }
                .disabled(!canZap)
                .help("Channel up: next in the list (↑)")
            volumeControl
            Spacer()
            Button { toggleFullScreen() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .help("Full screen (F)")
        }
        .font(.title3)
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .padding(.top, 50)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
    }

    private var controls: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomBar
        }
        .foregroundStyle(.white)
    }

    private var volumeControl: some View {
        HStack(spacing: 6) {
            Image(systemName: controller.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.callout)
                .frame(width: 22)
            Slider(value: Binding(get: { controller.volume }, set: { controller.setVolume($0) }), in: 0...150)
                .frame(width: 90)
                .controlSize(.small)
        }
    }
}

struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(.white).frame(width: 6, height: 6)
            Text("LIVE").font(.caption.weight(.bold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.red, in: RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(.white)
    }
}
