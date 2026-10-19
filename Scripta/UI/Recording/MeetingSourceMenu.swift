import SwiftUI

/// Menu items to start a meeting recording with a specific audio source.
struct MeetingSourceMenu: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Button("Gesamtes Systemaudio", systemImage: "speaker.wave.2") {
            Task { await appModel.startMeeting(.allSystemAudio) }
        }
        Section("Nur eine App") {
            if appModel.meetingApps.isEmpty {
                Text("Keine App spielt gerade Audio ab")
            }
            ForEach(appModel.meetingApps) { app in
                Button {
                    Task { await appModel.startMeeting(.application(app)) }
                } label: {
                    Label {
                        Text(app.name)
                    } icon: {
                        Image(nsImage: app.icon)
                    }
                }
            }
        }
        .onAppear { appModel.refreshMeetingApps() }
    }
}
