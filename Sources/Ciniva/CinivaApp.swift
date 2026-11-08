import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct CinivaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @State private var updater = Updater()

    init() {
        Prefs.register()
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
    }

    var body: some Scene {
        Window("Ciniva", id: "main") {
            RootView()
                .environment(model)
                .environment(updater)
                .frame(minWidth: 960, minHeight: 620)
                .task { updater.startAutomaticChecks() }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updater)
            }
            CommandGroup(after: .newItem) {
                OpenFileCommand(model: model)
            }
            CommandMenu("Library") {
                Button("Rescan Library") { Task { await model.rescan() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.client == nil || model.scanning)
            }
        }

        Settings {
            SettingsView().environment(model).environment(updater)
        }
    }
}

private struct OpenFileCommand: View {
    let model: AppModel

    var body: some View {
        Button("Open File…") {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.movie, .video, .audiovisualContent, .data]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            model.playFile(url)
        }
        .keyboardShortcut("o")
    }
}

private struct CheckForUpdatesCommand: View {
    let updater: Updater
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Check for Updates…") {
            Task { await updater.check(userInitiated: true) }
            openSettings()
        }
    }
}
