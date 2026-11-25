import SwiftUI

/// Settings › Erkennung: everything that turns audio into text and names:
/// the speech model, telling speakers apart, known voices, and the language
/// models for titles and summaries.
struct RecognitionSettingsView: View {
    var body: some View {
        Form {
            TranscriptionSettingsSections()
            PeopleSettingsSections()
            LanguageModelSettingsSections()
        }
        .formStyle(.grouped)
        .frame(height: 640)
    }
}
