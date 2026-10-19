import Foundation
import Testing
@testable import Scripta

@Suite("Update check")
@MainActor
final class UpdateCheckerTests {
    private let defaults: UserDefaults
    private let suiteName = "UpdateCheckerTests.\(UUID().uuidString)"

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Versions

    @Test("Versions parse from tags and plain strings", arguments: [
        ("0.2.0", [0, 2, 0]),
        ("v1.10.3", [1, 10, 3]),
        ("2", [2]),
    ])
    func parsing(string: String, components: [Int]) throws {
        #expect(try #require(AppVersion(string)).components == components)
    }

    @Test("Malformed versions are rejected", arguments: ["", "v", "1.x", "1..2", "0.2.0-beta"])
    func malformed(string: String) {
        #expect(AppVersion(string) == nil)
    }

    @Test("Versions compare numerically, missing components count as zero")
    func comparison() throws {
        func version(_ string: String) throws -> AppVersion { try #require(AppVersion(string)) }
        #expect(try version("0.1.0") < version("0.2.0"))
        #expect(try version("0.9.0") < version("0.10.0"))
        #expect(try version("1.0.1") > version("1.0"))
        #expect(try version("1.0") == version("1.0.0"))
        #expect(try version("v1.2.3").description == "1.2.3")
    }

    // MARK: - Checking

    @Test("A newer release is reported and remembered across launches")
    func newerRelease() async throws {
        let checker = makeChecker(running: "0.1.0", response: .release("v0.2.0"))
        let update = try #require(try await checker.check())
        #expect(update.version.description == "0.2.0")
        #expect(update.pageURL.absoluteString == "https://github.com/saibot-strg/scripta/releases/tag/v0.2.0")
        #expect(checker.availableUpdate == update)

        let relaunched = makeChecker(running: "0.1.0", response: .notFound)
        #expect(relaunched.availableUpdate == update)
        let updated = makeChecker(running: "0.2.0", response: .notFound)
        #expect(updated.availableUpdate == nil)
    }

    @Test("The same or an older release means up to date", arguments: ["v0.2.0", "v0.1.9"])
    func upToDate(tag: String) async throws {
        let checker = makeChecker(running: "0.2.0", response: .release(tag))
        #expect(try await checker.check() == nil)
        #expect(checker.availableUpdate == nil)
    }

    @Test("Without a published release the check fails with a clear error")
    func noRelease() async {
        let checker = makeChecker(running: "0.1.0", response: .notFound)
        await #expect(throws: UpdateChecker.CheckError.self) { try await checker.check() }
        #expect(checker.availableUpdate == nil)
    }

    @Test("A skipped version stays hidden until a newer one appears")
    func skipping() async throws {
        let checker = makeChecker(running: "0.1.0", response: .release("v0.2.0"))
        let update = try #require(try await checker.check())
        checker.skip(update)
        #expect(checker.availableUpdate == nil)

        let relaunched = makeChecker(running: "0.1.0", response: .release("v0.2.0"))
        #expect(relaunched.availableUpdate == nil)
        try await relaunched.check()
        #expect(relaunched.availableUpdate == nil)

        let later = makeChecker(running: "0.1.0", response: .release("v0.3.0"))
        try await later.check()
        #expect(later.availableUpdate?.version.description == "0.3.0")
    }

    @Test("Release pages outside github.com are never opened")
    func foreignPage() async throws {
        let checker = makeChecker(running: "0.1.0", response: .release("v0.2.0", page: "https://example.com/scripta.dmg"))
        let update = try #require(try await checker.check())
        #expect(update.pageURL == UpdateChecker.releasesPageURL)
    }

    @Test("Automatic checks run at most once a day and only when enabled")
    func automaticChecks() async {
        let counter = FetchCounter()
        let checker = makeChecker(running: "0.1.0", response: .release("v0.2.0"), counter: counter)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        await checker.checkIfDue(now: start)
        await checker.checkIfDue(now: start.addingTimeInterval(3_600))
        #expect(await counter.count == 1)

        await checker.checkIfDue(now: start.addingTimeInterval(UpdateChecker.checkInterval + 1))
        #expect(await counter.count == 2)

        defaults.set(false, forKey: SettingsKey.checksForUpdates)
        await checker.checkIfDue(now: start.addingTimeInterval(3 * UpdateChecker.checkInterval))
        #expect(await counter.count == 2)
    }

    @Test("Failed automatic checks are retried at the next wake-up")
    func failedCheckRetries() async {
        let counter = FetchCounter()
        let checker = makeChecker(running: "0.1.0", response: .serverError, counter: counter)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        await checker.checkIfDue(now: start)
        await checker.checkIfDue(now: start.addingTimeInterval(60))
        #expect(await counter.count == 2)
    }

    @Test("Unit tests are recognized, so the app host never asks GitHub")
    func testsDontReachGitHub() {
        #expect(UpdateChecker.isRunningTests)
    }

    // MARK: - Helpers

    private enum Response {
        case release(String, page: String? = nil)
        case notFound
        case serverError
    }

    private func makeChecker(running version: String, response: Response, counter: FetchCounter = FetchCounter()) -> UpdateChecker {
        let (status, body): (Int, String) = switch response {
        case .release(let tag, let page):
            (200, #"{"tag_name": "\#(tag)", "html_url": "\#(page ?? "https://github.com/saibot-strg/scripta/releases/tag/\(tag)")", "draft": false}"#)
        case .notFound:
            (404, #"{"message": "Not Found"}"#)
        case .serverError:
            (500, "")
        }
        return UpdateChecker(currentVersion: AppVersion(version)!, defaults: defaults) {
            await counter.increment()
            let response: URLResponse = HTTPURLResponse(url: UpdateChecker.latestReleaseURL, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }
}

private actor FetchCounter {
    private(set) var count = 0

    func increment() { count += 1 }
}
