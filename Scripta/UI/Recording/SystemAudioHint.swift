import AppKit
import SwiftUI

/// Shown when apps play sound but the meeting's system track stays silent.
struct SystemAudioHint: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.slash.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kein Systemton")
                    .font(.callout.weight(.semibold))
                Text("Erlaube Scripta die Systemaudio-Aufnahme und starte das Meeting neu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("Öffnen") {
                if let url = PrivacyPane.systemAudio.url { NSWorkspace.shared.open(url) }
            }
            .help("Systemeinstellungen › Datenschutz & Sicherheit › Bildschirm- & Systemaudioaufnahme")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}
