import CinivaKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView("Connecting to Ciniva…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                SignInView()
            case .ready:
                BrowserView()
            }
        }
        .overlay {
            if model.playback != nil {
                PlayerScreen().transition(.opacity)
            }
        }
        .overlay { ToastOverlay() }
        .animation(.easeInOut(duration: 0.2), value: model.playback?.id)
        .task {
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--play"), i + 1 < args.count {
                model.playFile(URL(fileURLWithPath: args[i + 1]))
            }
            if model.phase == .loading { await model.bootstrap() }
        }
    }
}

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case server, username, password }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 18) {
            Image(systemName: "play.rectangle.on.rectangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(accent)
            Text("Ciniva").font(.largeTitle.bold())
            Text("Sign in to your Ciniva server").foregroundStyle(.secondary)

            VStack(spacing: 10) {
                TextField("Server", text: $model.serverText, prompt: Text(AppModel.defaultServer))
                    .focused($focus, equals: .server)
                    .onSubmit { focus = .username }
                TextField("Username", text: $model.usernameText)
                    .textContentType(.username)
                    .focused($focus, equals: .username)
                    .onSubmit { focus = .password }
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .onSubmit(submit)
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 320)
            .disabled(model.isSigningIn)

            if model.isSigningIn {
                ProgressView().controlSize(.small)
            } else {
                Button(action: submit) { Text("Sign In").frame(minWidth: 200) }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            if model.hasStoredSession && !model.isSigningIn {
                Button("Try Again") { Task { await model.bootstrap() } }
            }
            if let e = model.errorMessage {
                Text(e).foregroundStyle(.red).multilineTextAlignment(.center).frame(maxWidth: 420)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focus = model.usernameText.isEmpty ? .username : .password }
    }

    private func submit() {
        let pw = password
        Task {
            await model.signIn(password: pw)
            if model.phase == .ready { password = "" }
        }
    }
}

struct BrowserView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var columns: NavigationSplitViewVisibility = .automatic
    @State private var columnsBeforePlayback: NavigationSplitViewVisibility?

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $model.selection) {
                Label("Home", systemImage: "house").tag(SidebarItem.home)
                Section("Library") {
                    Label("Movies", systemImage: "film").tag(SidebarItem.movies)
                    Label("Shows", systemImage: "tv").tag(SidebarItem.shows)
                }
                if !model.navPlugins.isEmpty {
                    Section("Plugins") {
                        ForEach(model.navPlugins, id: \.1.id) { p, page in
                            Label(page.title, systemImage: symbol(for: page.icon ?? p.icon))
                                .help(p.name)
                                .tag(SidebarItem.plugin(p.id, page.id))
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    UpdateBanner()
                    accountMenu
                }
            }
        } detail: {
            NavigationStack(path: $model.path) {
                Group {
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        SearchResultsView(query: query)
                    } else {
                        switch model.selection {
                        case .movies: LibraryGridView(kind: .movies).id("movies")
                        case .shows: LibraryGridView(kind: .shows).id("shows")
                        case .plugin(let id, let page): PluginPageView(pluginId: id, nav: PluginNav(page: page)).id("\(id)/\(page)")
                        default: HomeView()
                        }
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .movie(let id): MovieDetailView(id: id)
                    case .show(let id): ShowDetailView(id: id)
                    case .plugin(let id, let nav): PluginPageView(pluginId: id, nav: nav)
                    }
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search movies & shows")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.rescan() }
                } label: {
                    if model.scanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Rescan Library", systemImage: "arrow.clockwise")
                    }
                }
                .help("Rescan the library for new and removed files")
                .disabled(model.scanning || model.client == nil)
            }
        }
        .toolbar(model.playback == nil ? .automatic : .hidden, for: .windowToolbar)
        .onChange(of: model.selection) { model.path = [] }
        .onChange(of: model.playback == nil, initial: true) { _, closed in
            // The sidebar's titlebar area shows through when full screen reveals the titlebar over the player.
            if closed {
                columns = columnsBeforePlayback ?? .automatic
                columnsBeforePlayback = nil
            } else {
                columnsBeforePlayback = columns
                columns = .detailOnly
            }
        }
        .sheet(item: $model.pluginSheet) { sheet in
            PluginSheetView(sheet: sheet)
        }
    }

    private var accountMenu: some View {
        Menu {
            if let host = model.client?.baseURL.host() { Text(host) }
            Divider()
            SettingsLink { Text("Settings…") }
            Button("Rescan Library") { Task { await model.rescan() } }
            Button("Reload Plugins") { Task { await model.loadPlugins() } }
            Divider()
            Button("Sign Out") { model.signOut() }
        } label: {
            Label(model.user?.username ?? "Account", systemImage: "person.crop.circle")
        }
        .menuStyle(.borderlessButton)
        .padding(12)
    }
}

private struct UpdateBanner: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        if let r = updater.available {
            Button {
                Task { await updater.install(r) }
            } label: {
                Label("Update to \(r.version)", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .help("Download Ciniva \(r.version), install it and relaunch")
            .padding(.horizontal, 12)
            .padding(.top, 8)
        } else if updater.phase == .installing {
            HStack { ProgressView().controlSize(.small); Text("Updating…").font(.callout) }
                .padding(.horizontal, 12)
                .padding(.top, 8)
        }
    }
}
