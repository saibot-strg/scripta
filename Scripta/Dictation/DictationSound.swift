import AppKit

/// Quiet system sounds when dictation starts and stops, so the user hears it
/// where they look (the text field), not only in the HUD at the screen edge.
enum DictationSound {
    case start
    case stop

    private var name: NSSound.Name {
        switch self {
        case .start: "Tink"
        case .stop: "Pop"
        }
    }

    @MainActor
    func play() {
        // A fresh instance each time: a playing NSSound doesn't restart.
        guard let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = 0.4
        sound.play()
    }
}
