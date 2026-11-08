import AppKit
import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class Updater {
    struct Release: Equatable {
        let version: String
        let notes: String
        let archive: URL
        let signature: URL
    }

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing
        case failed(String)
    }

    nonisolated static let repository = "Ciniva/ciniva-macos"
    nonisolated static let publicKey = "LOrx2enHLJTnamVfTCugE+Hp6TKjKOv4BobPlUO8lQ4="

    var phase: Phase = .idle
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    var available: Release? {
        if case .available(let r) = phase { return r }
        return nil
    }

    @ObservationIgnored private var loop: Task<Void, Never>?

    func startAutomaticChecks() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                if UserDefaults.standard.object(forKey: Prefs.autoUpdateCheck) as? Bool ?? true {
                    await self?.check(userInitiated: false)
                }
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    func check(userInitiated: Bool) async {
        if phase == .installing { return }
        phase = .checking
        do {
            if let r = try await Self.latestRelease(), Self.isNewer(r.version, than: currentVersion) {
                phase = .available(r)
            } else {
                phase = .upToDate
            }
        } catch {
            phase = userInitiated ? .failed("Couldn't check for updates: \(error.localizedDescription)") : .idle
        }
    }

    func install(_ release: Release) async {
        phase = .installing
        do {
            let target = Bundle.main.bundleURL
            if target.path.contains("/AppTranslocation/") {
                throw UpdateError("Move Ciniva to the Applications folder first, then install the update.")
            }
            let (archive, _) = try await URLSession.shared.download(from: release.archive)
            let (signature, _) = try await URLSession.shared.data(from: release.signature)
            let data = try Data(contentsOf: archive)
            try Self.verify(data, signature: signature)

            let fm = FileManager.default
            let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
            defer { try? fm.removeItem(at: work) }
            let zip = work.appending(path: "update.zip")
            try data.write(to: zip)
            try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let fresh = work.appending(path: "Ciniva.app")
            guard Bundle(url: fresh)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw UpdateError("The downloaded update isn't a Ciniva app.")
            }
            _ = try fm.replaceItemAt(target, withItemAt: fresh)
            Self.relaunch(target)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Helpers

    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    nonisolated static func verify(_ data: Data, signature: Data, publicKey: String = publicKey) throws {
        let text = String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: publicKey), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              let sig = Data(base64Encoded: text), key.isValidSignature(sig, for: data)
        else { throw UpdateError("The update's signature is invalid; it was not installed.") }
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }

        let tagName: String
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    private static func latestRelease() async throws -> Release? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }
        guard code == 200 else { throw UpdateError("GitHub returned HTTP \(code).") }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let r = try d.decode(GitHubRelease.self, from: data)
        guard !r.draft, !r.prerelease,
              let zip = r.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let sig = r.assets.first(where: { $0.name == zip.name + ".sig" })
        else { return nil }
        let version = r.tagName.hasPrefix("v") ? String(r.tagName.dropFirst()) : r.tagName
        return Release(version: version, notes: r.body ?? "", archive: zip.browserDownloadUrl, signature: sig.browserDownloadUrl)
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError("\(tool) failed (\(p.terminationStatus)).") }
    }

    private static func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }
}

struct UpdateError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
