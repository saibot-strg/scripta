import AppKit
import CoreAudio

/// What a meeting recording captures besides the microphone.
enum SystemAudioTarget: Hashable, Sendable {
    /// Everything the Mac plays, except Scripta itself.
    case allSystemAudio
    /// Only one app (including its helper processes, e.g. browser audio services).
    case application(MeetingApp)

    var displayName: String {
        switch self {
        case .allSystemAudio: String(localized: "Gesamtes Systemaudio")
        case .application(let app): app.name
        }
    }
}

/// A running app whose audio can be recorded.
struct MeetingApp: Hashable, Sendable, Identifiable {
    let bundleID: String
    let name: String
    let bundleURL: URL

    var id: String { bundleID }

    @MainActor
    var icon: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: bundleURL.path(percentEncoded: false))
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

/// Finds apps that play audio and the Core Audio processes behind them.
@MainActor
enum AudioAppCatalog {
    /// Apps that commonly carry meeting audio. Listed even before they open an
    /// audio stream, because the tap follows them by bundle ID.
    private static let knownMeetingApps: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.cisco.webexmeetingsapp",
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.apple.Safari", "com.google.Chrome",
        "org.mozilla.firefox", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.brave.Browser",
        "net.whatsapp.WhatsApp", "org.whispersystems.signal-desktop", "com.skype.skype",
    ]

    /// Safari plays web audio in a shared WebKit process outside its bundle.
    private static let webKitAudioBundleID = "com.apple.WebKit.GPU"

    /// Running apps that use audio, known meeting apps first.
    static func availableApps() -> [MeetingApp] {
        let ownBundleID = Bundle.main.bundleIdentifier
        var apps: [String: MeetingApp] = [:]

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, bundleID != ownBundleID, let url = app.bundleURL else { continue }
            if knownMeetingApps.contains(bundleID) {
                apps[bundleID] = MeetingApp(bundleID: bundleID, name: app.localizedName ?? bundleID, bundleURL: url)
            }
        }
        for process in audioProcesses() {
            guard let owner = owningApp(of: process), owner.bundleID != ownBundleID else { continue }
            apps[owner.bundleID] = owner
        }

        return apps.values.sorted { lhs, rhs in
            let lhsKnown = knownMeetingApps.contains(lhs.bundleID)
            let rhsKnown = knownMeetingApps.contains(rhs.bundleID)
            if lhsKnown != rhsKnown { return lhsKnown }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func app(withBundleID bundleID: String) -> MeetingApp? {
        availableApps().first { $0.bundleID == bundleID }
    }

    /// Process objects and bundle IDs to tap for an app (main app plus helpers).
    static func tapMembers(for app: MeetingApp) -> (processes: [AudioObjectID], bundleIDs: [String]) {
        var processes: [AudioObjectID] = []
        var bundleIDs: Set<String> = [app.bundleID]
        for process in audioProcesses() {
            guard owningApp(of: process)?.bundleID == app.bundleID else { continue }
            processes.append(process.id)
            if let bundleID = try? process.bundleID { bundleIDs.insert(bundleID) }
        }
        return (processes, bundleIDs.sorted())
    }

    /// True if any process other than Scripta is currently playing audio.
    static func isOtherAudioPlaying() -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return audioProcesses().contains { process in
            (try? process.pid) != ownPID && (try? process.isRunningOutput) == true
        }
    }

    private static func audioProcesses() -> [AudioHardwareProcess] {
        (try? AudioHardwareSystem.shared.processes) ?? []
    }

    /// The `.app` a process belongs to: helper processes live inside the main
    /// app bundle, so the outermost `.app` in their path is the owner.
    private static func owningApp(of process: AudioHardwareProcess) -> MeetingApp? {
        guard let pid = try? process.pid, let running = NSRunningApplication(processIdentifier: pid) else { return nil }

        if running.bundleIdentifier == webKitAudioBundleID {
            guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first,
                  let url = safari.bundleURL else { return nil }
            return MeetingApp(bundleID: "com.apple.Safari", name: safari.localizedName ?? "Safari", bundleURL: url)
        }

        guard let url = running.bundleURL,
              let appIndex = url.pathComponents.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let appURL = URL(filePath: NSString.path(withComponents: Array(url.pathComponents[...appIndex])))
        guard let bundle = Bundle(url: appURL), let bundleID = bundle.bundleIdentifier,
              let owner = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              owner.activationPolicy == .regular else { return nil }
        return MeetingApp(bundleID: bundleID, name: owner.localizedName ?? bundleID, bundleURL: appURL)
    }
}
