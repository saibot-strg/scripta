import SwiftUI

/// Known people not in this meeting yet, and the other speakers of this
/// meeting (choosing one merges). A known person who already is a speaker
/// here appears only once, as a speaker: both would merge anyway.
struct SpeakerChoicesMenu: View {
    @Environment(AppModel.self) private var appModel
    let speaker: SpeakerLabel
    let speakers: [SpeakerLabel]
    @Binding var names: [UUID: String]

    var body: some View {
        // Each name once: speakers with the same name are merged on "Fertig" anyway.
        var seen: Set<String> = []
        let others = speakers.filter { other in
            other.id != speaker.id && seen.insert((names[other.id] ?? other.displayName).lowercased()).inserted
        }
        let present = seen
        let people = appModel.voices.people.filter { !present.contains($0.name.lowercased()) }

        Menu("Bekannte Person oder anderen Sprecher wählen", systemImage: "person.crop.circle") {
            if !people.isEmpty {
                Section("Aus früheren Meetings") {
                    ForEach(people) { person in
                        Button(person.name) { names[speaker.id] = person.name }
                    }
                }
            }
            if !others.isEmpty {
                Section("Zusammenführen mit") {
                    ForEach(others) { other in
                        let name = names[other.id] ?? other.displayName
                        Button(name) { names[speaker.id] = name }
                    }
                }
            }
        }
        .labelStyle(.iconOnly)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Bekannte Person oder anderen Sprecher wählen")
    }
}
