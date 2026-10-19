import AppKit
import Foundation
import os

/// Dotted numeric version such as "0.2.0"; a leading "v" (Git tag) is ignored.
struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let components: [Int]

    init?(_ string: String) {
        let numbers = string.trimmingPrefix("v")
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { Int($0) }
        guard !numbers.isEmpty, !numbers.contains(nil) else { return nil }
        components = numbers.compactMap(\.self)
    }

    /// The running app's version (CFBundleShortVersionString).
    static let current = AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        ?? AppVersion("0")!

    var description: String { components.map(String.init).joined(separator: ".") }

    // Missing components count as zero, so "1.0" equals "1.0.0".
    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = lhs.component(at: index)
            let right = rhs.component(at: index)
            if left != right { return left < right }
        }
        return false
    }

    private func component(at index: Int) -> Int {
        components.indices.contains(index) ? components[index] : 0
    }
}

/// Looks for a newer Scripta release on GitHub. There is no auto-updater: a
/// new version only points the user to its release page with the DMG.
///
/// The request is a plain HTTPS GET without identifiers, cookies or usage data.
/// Automatic checks run at most once a day and can be turned off in the settings.
@MainActor
@Observable
final class UpdateChecker {
    struct Update: Equatable, Sendable {
        let version: AppVersion
        /// Release page with the DMG and the install notes.
        let pageURL: URL
    }

    enum CheckError: LocalizedError {
        case noRelease
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .noRelease:
                String(localized: "Auf GitHub wurde keine veröffentlichte Version gefunden.")
            case .badResponse(let status):
                String(localized: "GitHub hat mit Fehler \(status) geantwortet.")
            }
        }
    }

    nonisolated static let latestReleaseURL = URL(string: "https://api.github.com/repos/saibot-strg/scripta/releases/latest")!
    nonisolated static let releasesPageURL = URL(string: "https://github.com/saibot-strg/scripta/releases/latest")!
    /// Minimum time between two automatic checks.
    static let checkInterval: TimeInterval = 24 * 60 * 60
    /// How often a long-running Scripta looks whether a check is due.
    static let wakeInterval: Duration = .seconds(6 * 60 * 60)

    /// Newer release than this app, unless the user skipped it. Kept across
    /// launches, so the note stays until the user updates or skips it.
    private(set) var availableUpdate: Update?
    private(set) var isChecking = false

    let currentVersion: AppVersion
    private let defaults: UserDefaults
    private let fetch: @Sendable () async throws -> (Data, URLResponse)
    private var automaticChecks: Task<Void, Never>?

    init(
        currentVersion: AppVersion = .current,
        defaults: UserDefaults = .standard,
        fetch: @escaping @Sendable () async throws -> (Data, URLResponse) = UpdateChecker.fetchLatestRelease
    ) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.fetch = fetch
        if let version = defaults.string(forKey: SettingsKey.latestReleaseVersion).flatMap(AppVersion.init),
           let pageURL = defaults.url(forKey: SettingsKey.latestReleasePage) {
            availableUpdate = visible(Update(version: version, pageURL: pageURL))
        }
    }

    /// On unless turned off in the settings.
    var checksAutomatically: Bool {
        defaults.object(forKey: SettingsKey.checksForUpdates) as? Bool ?? true
    }

    /// Unit tests run inside the app and must not reach GitHub.
    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Checks at launch and keeps checking while Scripta runs (it may stay
    /// open for days for dictation); `checkIfDue` limits it to once a day.
    func startAutomaticChecks() {
        guard automaticChecks == nil, !Self.isRunningTests else { return }
        automaticChecks = Task {
            while !Task.isCancelled {
                await checkIfDue()
                try? await Task.sleep(for: Self.wakeInterval)
            }
        }
    }

    /// Automatic check: only when enabled and due. Failures stay silent and
    /// are retried at the next wake-up, since only successful checks count.
    func checkIfDue(now: Date = .now) async {
        guard checksAutomatically, !isChecking else { return }
        if let lastCheck = defaults.object(forKey: SettingsKey.lastUpdateCheck) as? Date,
           now.timeIntervalSince(lastCheck) < Self.checkInterval {
            return
        }
        do {
            try await check(now: now)
        } catch {
            Logger.app.info("Update check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Fetches the latest release and returns it if it is newer than this app.
    @discardableResult
    func check(now: Date = .now) async throws -> Update? {
        isChecking = true
        defer { isChecking = false }

        let (data, response) = try await fetch()
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            // 404: no published release yet (or the repository isn't public).
            throw status == 404 ? CheckError.noRelease : CheckError.badResponse(status)
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let version = AppVersion(release.tagName) else { throw CheckError.noRelease }
        // Only ever open GitHub pages, whatever the response says.
        let pageURL = release.htmlURL.scheme == "https" && release.htmlURL.host() == "github.com"
            ? release.htmlURL : Self.releasesPageURL
        let latest = Update(version: version, pageURL: pageURL)

        defaults.set(now, forKey: SettingsKey.lastUpdateCheck)
        defaults.set(version.description, forKey: SettingsKey.latestReleaseVersion)
        defaults.set(pageURL, forKey: SettingsKey.latestReleasePage)
        availableUpdate = visible(latest)
        Logger.app.notice("Update check: latest \(version.description, privacy: .public), running \(self.currentVersion.description, privacy: .public)")
        return version > currentVersion ? latest : nil
    }

    /// "Check for Updates …": checks right away and reports the result in an alert.
    func checkNow() async {
        guard !isChecking else { return }
        let alert = NSAlert()
        do {
            if let update = try await check() {
                alert.messageText = String(localized: "Scripta \(update.version.description) ist verfügbar")
                alert.informativeText = String(localized: "Du verwendest Version \(currentVersion.description). Lade die neue Version herunter und ersetze Scripta im Programme-Ordner damit.")
                alert.addButton(withTitle: String(localized: "Download-Seite öffnen"))
                alert.addButton(withTitle: String(localized: "Später"))
                NSApp.activate()
                if alert.runModal() == .alertFirstButtonReturn { openReleasePage(for: update) }
                return
            }
            alert.messageText = String(localized: "Scripta ist auf dem neuesten Stand")
            alert.informativeText = String(localized: "Version \(currentVersion.description) ist die aktuelle Version.")
        } catch {
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Suche nach Updates fehlgeschlagen")
            alert.informativeText = error.localizedDescription
        }
        NSApp.activate()
        alert.runModal()
    }

    func openReleasePage(for update: Update) {
        NSWorkspace.shared.open(update.pageURL)
    }

    /// Hides the note for this version; a later release shows it again.
    func skip(_ update: Update) {
        defaults.set(update.version.description, forKey: SettingsKey.skippedUpdateVersion)
        availableUpdate = nil
    }

    #if DEBUG
    /// Shows the update note without asking GitHub (`-SimulateUpdate`).
    func simulateUpdate(to version: AppVersion) {
        availableUpdate = Update(version: version, pageURL: Self.releasesPageURL)
    }
    #endif

    /// The update if it is newer than this app and not skipped.
    private func visible(_ update: Update) -> Update? {
        guard update.version > currentVersion,
              update.version.description != defaults.string(forKey: SettingsKey.skippedUpdateVersion) else { return nil }
        return update
    }

    nonisolated static func fetchLatestRelease() async throws -> (Data, URLResponse) {
        var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return try await session.data(for: request)
    }

    /// No cookies, no cache on disk.
    nonisolated private static let session = URLSession(configuration: .ephemeral)
}

/// The fields of GitHub's "latest release" response that matter here.
private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
