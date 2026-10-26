import SwiftUI

/// The dictation pill: level meter while recording, then the result.
struct DictationHUDView: View {
    let controller: DictationController
    let presentation: HUDPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            DictationHUDContent(controller: controller, reduceMotion: reduceMotion)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 16)
        .frame(width: 280, height: 46)
        .glassEffect(.regular, in: .capsule)
        // Rises out of the bottom edge and sinks back the same way; with
        // Reduce Motion it only fades.
        .scaleEffect(presentation.isShown || reduceMotion ? 1 : 0.92, anchor: .bottom)
        .offset(y: presentation.isShown || reduceMotion ? 0 : 10)
        .opacity(presentation.isShown ? 1 : 0)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.3, bounce: 0), value: presentation.isShown)
        .frame(width: 300, height: 64)
        .animation(.smooth(duration: 0.2), value: controller.phase)
        .onChange(of: controller.phase) { _, phase in
            announce(phase)
        }
    }

    /// The panel never takes focus, so VoiceOver hears the result this way.
    private func announce(_ phase: DictationController.Phase) {
        switch phase {
        case .finished(let result):
            AccessibilityNotification.Announcement(result.message).post()
        case .failed(let message):
            AccessibilityNotification.Announcement(message).post()
        case .idle, .recording, .transcribing:
            break
        }
    }
}
