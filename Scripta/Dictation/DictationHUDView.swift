import SwiftUI

/// The dictation pill: small and midnight blue while dictating, like a small
/// app icon (it stands out by contrast, not size), a circle for the
/// checkmark, wide and light only for messages that need reading.
struct DictationHUDView: View {
    let controller: DictationController
    let presentation: HUDPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Dictating, recognizing and the checkmark; not the messages.
    private var isCompact: Bool {
        switch controller.phase {
        case .idle, .recording, .transcribing: true
        case .finished(let result): result.isSuccess
        case .failed: false
        }
    }

    private var pillSize: CGSize {
        switch controller.phase {
        case .idle, .recording, .transcribing: CGSize(width: 58, height: 26)
        case .finished(let result) where result.isSuccess: CGSize(width: 26, height: 26)
        case .finished, .failed: CGSize(width: 300, height: 46)
        }
    }

    var body: some View {
        let size = pillSize
        HStack(spacing: 6) {
            DictationHUDContent(controller: controller, reduceMotion: reduceMotion)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, size.width == size.height ? 0 : isCompact ? 10 : 16)
        .frame(width: size.width, height: size.height)
        .glassEffect(isCompact ? .regular.tint(Color.brandMidnight.opacity(0.85)) : .regular, in: .capsule)
        .environment(\.colorScheme, isCompact ? .dark : colorScheme)
        // Pops up out of the bottom edge, so the eye notices it, and sinks
        // back without bounce; with Reduce Motion it only fades.
        .scaleEffect(presentation.isShown || reduceMotion ? 1 : 0.6, anchor: .bottom)
        .offset(y: presentation.isShown || reduceMotion ? 0 : 8)
        .opacity(presentation.isShown ? 1 : 0)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2)
                : presentation.isShown ? .spring(duration: 0.35, bounce: 0.35) : .spring(duration: 0.25, bounce: 0),
            value: presentation.isShown
        )
        // Bottom-aligned, so the pill grows upwards and sideways from where it sits.
        .padding(.bottom, 9)
        .frame(width: HUDPanel.size.width, height: HUDPanel.size.height, alignment: .bottom)
        .animation(.smooth(duration: 0.25), value: controller.phase)
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
