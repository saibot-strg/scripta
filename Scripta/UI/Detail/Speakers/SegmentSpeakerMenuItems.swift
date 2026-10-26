import SwiftUI

/// Who one passage belongs to. Choosing changes only this passage; the last
/// entry renames all passages of its speaker.
struct SegmentSpeakerMenuItems: View {
    @Environment(AppModel.self) private var appModel
    let segment: TranscriptSegment
    let onAssignAll: (SpeakerLabel) -> Void

    var body: some View {
        let current = segment.speaker
        let speakers = (segment.transcript?.speakers ?? [])
            .filter { $0.id != current?.id }
            .sorted(by: SpeakerLabel.menuOrder)
        let present = Set((segment.transcript?.speakers ?? []).map { $0.displayName.lowercased() })
        let people = appModel.voices.people.filter { !present.contains($0.name.lowercased()) }

        Section("Diese Sprechblase gehört zu") {
            ForEach(speakers) { speaker in
                Button(speaker.displayName) { appModel.move(segment, to: speaker) }
            }
            ForEach(people) { person in
                Button(person.name) { appModel.moveToNewSpeaker(segment, named: person.name) }
            }
            Button("Neuer Sprecher", systemImage: "person.badge.plus") {
                appModel.moveToNewSpeaker(segment)
            }
        }
        if let current {
            Divider()
            if current.isGuess(in: appModel.voices) {
                Button("„\(current.displayName)“ bestätigen", systemImage: "checkmark.circle") {
                    appModel.confirmSuggestion(for: current)
                }
            }
            Button("Alle von „\(current.displayName)“ benennen …", systemImage: "person.2") {
                onAssignAll(current)
            }
        }
    }
}
