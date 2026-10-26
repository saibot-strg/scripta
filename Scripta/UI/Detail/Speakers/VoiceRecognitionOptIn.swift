import SwiftUI

/// Invitation in the assignment sheet to turn on voice recognition.
struct VoiceRecognitionOptIn: View {
    @Binding var recognizesVoices: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.badge.shield.checkmark")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Stimmen wiedererkennen")
                    .font(.headline)
                Text("Scripta kann sich die Stimmen merken, die du benennst, und schlägt die Namen in späteren Aufnahmen vor. Stimmprofile sind biometrische Daten: Sie bleiben auf diesem Mac und lassen sich in den Einstellungen jederzeit löschen. Frag die Personen, ob das für sie in Ordnung ist.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Einschalten") { recognizesVoices = true }
            }
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }
}
