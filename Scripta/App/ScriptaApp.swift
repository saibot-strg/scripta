import SwiftData
import SwiftUI
import os

@main
struct ScriptaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer
    @State private var appModel: AppModel
    @AppStorage(SettingsKey.showsMenuBarIcon) private var showsMenuBarIcon = true

    init() {
        let container: ModelContainer
        var startupError: PresentableError?
        do {
            container = try ModelContainerFactory.makePersistent()
        } catch {
            // Keep the app usable and tell the user instead of crashing.
            Logger.app.fault("Library store unavailable: \(error.localizedDescription, privacy: .public)")
            container = ModelContainerFactory.makeInMemory()
            startupError = PresentableError(error)
        }
        self.container = container

        let model = AppModel(library: LibraryService(modelContext: container.mainContext, locations: StorageLocations()))
        if let startupError { model.presentedError = startupError }
        Task { await model.performStartupMaintenance() }
        #if DEBUG
        DebugLaunchOptions.apply(to: model)
        #endif
        _appModel = State(initialValue: model)
    }

    var body: some Scene {
        Window("Scripta", id: "main") {
            ContentView()
                .environment(appModel)
                .onAppear { appDelegate.appModel = appModel }
        }
        .modelContainer(container)
        .defaultSize(width: 1180, height: 760)
        .commands {
            AppCommands(appModel: appModel)
        }

        Settings {
            SettingsView()
                .environment(appModel)
        }

        // MenuBarExtra writes `isInserted` back on every update; writing the
        // same value to UserDefaults would trigger another update, endlessly.
        MenuBarExtra(isInserted: Binding(
            get: { showsMenuBarIcon },
            set: { if $0 != showsMenuBarIcon { showsMenuBarIcon = $0 } }
        )) {
            MenuBarContent()
                .environment(appModel)
        } label: {
            MenuBarLabel(recorder: appModel.recorder)
        }
    }
}
