import SwiftUI

/// Voice recognition: opt-in, known people, deleting voice profiles.
struct PeopleSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingsKey.recognizesVoices) private var recognizesVoices = false
    @State private var personToRename: PersonSummary?
    @State private var newName = ""
    @State private var personToDelete: PersonSummary?
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        let people = appModel.voices.people
        Form {
            Section {
                Toggle(isOn: $recognizesVoices) {
                    Text("Stimmen wiedererkennen")
                    Text("Scripta merkt sich die Stimmen der Personen, die du in Transkripten benennst, und erkennt sie in späteren Aufnahmen wieder.")
                }
            } footer: {
                Text("Stimmprofile sind biometrische Daten. Sie bleiben auf diesem Mac und lassen sich hier jederzeit löschen. Frag die Personen, ob das für sie in Ordnung ist.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if people.isEmpty {
                    Text("Noch niemand. Benenne Sprecher in einem Transkript, dann merkt sich Scripta ihre Stimmen.")
                        .foregroundStyle(.secondary)
                }
                ForEach(people) { person in
                    LabeledContent {
                        Menu("Aktionen für \(person.name)", systemImage: "ellipsis.circle") {
                            Button("Umbenennen …") {
                                newName = person.name
                                personToRename = person
                            }
                            Button("Löschen …", role: .destructive) { personToDelete = person }
                        }
                        .labelStyle(.iconOnly)
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    } label: {
                        Text(person.name)
                        Text(details(of: person))
                    }
                }
            } header: {
                Text("Personen")
            } footer: {
                Text("Ab \(VoiceMatcher.confirmedSamplesForAutomatic) bestätigten Stimmproben setzt Scripta den Namen selbst, vorher schlägt es ihn vor.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Alle Stimmprofile löschen …", role: .destructive) { isConfirmingDeleteAll = true }
                    .disabled(people.isEmpty && appModel.voices.statuses.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
        .alert("Person umbenennen", item: $personToRename) { person in
            TextField("Name", text: $newName)
            Button("Umbenennen") {
                appModel.renamePerson(person.id, to: newName)
            }
            .keyboardShortcut(.defaultAction)
            Button("Abbrechen", role: .cancel) {}
        } message: { _ in
            Text("Der Name ändert sich auch in allen Transkripten, in denen die Person erkannt oder benannt wurde.")
        }
        .confirmationDialog("„\(personToDelete?.name ?? "")“ löschen?", item: $personToDelete) { person in
            Button("Löschen", role: .destructive) {
                appModel.deletePerson(person.id)
            }
        } message: { _ in
            Text("Die Stimmproben werden gelöscht. Namen in Transkripten bleiben stehen.")
        }
        .confirmationDialog("Alle Stimmprofile löschen?", isPresented: $isConfirmingDeleteAll) {
            Button("Alle löschen", role: .destructive) { appModel.deleteAllVoiceProfiles() }
        } message: {
            Text("Alle Personen, Stimmproben und Stimm-Fingerabdrücke werden gelöscht. Namen in Transkripten bleiben stehen.")
        }
    }

    private func details(of person: PersonSummary) -> String {
        let confirmed = String(localized: "Bestätigte Stimmproben: \(person.confirmedSamples)")
        let mode = person.confirmedSamples >= VoiceMatcher.confirmedSamplesForAutomatic
            ? String(localized: "wird automatisch erkannt")
            : String(localized: "wird vorgeschlagen")
        return "\(confirmed) · \(mode)"
    }
}
