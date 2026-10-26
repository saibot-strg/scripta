import ServiceManagement
import SwiftUI

/// Settings › Allgemein: language, appearance, behaviour, updates.
struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingsKey.checksForUpdates) private var checksForUpdates = true
    /// Off by default: recording and transcribing are separate steps.
    @AppStorage(SettingsKey.autoTranscribe) private var autoTranscribe = false
    @AppStorage(SettingsKey.appearance) private var appearance: AppAppearance = .system
    @AppStorage(SettingsKey.showsMenuBarIcon) private var showsMenuBarIcon = true
    @State private var language = AppLanguage.stored()
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Picker("Sprache", selection: $language) {
                    ForEach(AppLanguage.allCases) { language in
                        if let name = language.nativeName {
                            Text(verbatim: name).tag(language)
                        } else {
                            Text("Wie System").tag(language)
                        }
                    }
                }
                .onChange(of: language) { language.store() }
                if language != AppLanguage.atLaunch {
                    LabeledContent {
                        Button("Jetzt neu starten", action: appModel.relaunch)
                            .disabled(!appModel.canRelaunch)
                    } label: {
                        Text("Gilt nach einem Neustart von Scripta.")
                        if !appModel.canRelaunch {
                            Text("Möglich, sobald die Aufnahme gespeichert ist.")
                        }
                    }
                }
                Picker("Erscheinungsbild", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { appearance.apply() }
            }
            Section {
                Toggle("Automatisch transkribieren", isOn: $autoTranscribe)
            } footer: {
                Text("Neue Aufnahmen und Importe werden direkt in die Warteschlange gestellt.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Symbol in der Menüleiste", isOn: $showsMenuBarIcon)
                Toggle("Beim Anmelden starten", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, enabled in updateLoginItem(enabled) }
            } footer: {
                Text("Praktisch für das Diktat: Das Tastenkürzel funktioniert, solange Scripta läuft.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Automatisch nach Updates suchen", isOn: $checksForUpdates)
                    .onChange(of: checksForUpdates) { _, enabled in
                        if enabled { Task { await appModel.updates.checkIfDue() } }
                    }
                LabeledContent("Version \(appModel.updates.currentVersion.description)") {
                    Button("Jetzt suchen", action: checkForUpdates)
                        .disabled(appModel.updates.isChecking)
                }
            } footer: {
                Text("Scripta fragt einmal am Tag bei GitHub nach, ob es eine neue Version gibt. Daten über deine Aufnahmen oder deine Nutzung werden dabei nicht übertragen.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
        .alert("„Beim Anmelden starten“ ließ sich nicht ändern", isPresented: $loginItemError.isPresent, presenting: loginItemError) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    private func updateLoginItem(_ enabled: Bool) {
        // Also called when the toggle is set back below; nothing to do then.
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginItemError = error.localizedDescription
            launchesAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func checkForUpdates() {
        Task { await appModel.updates.checkNow() }
    }
}
