import AppKit

/// Credits in the About panel, including the licenses that require attribution.
enum AboutCredits {
    @MainActor
    static var text: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        let lines = [
            String(localized: "Lokale Transkription. Audio und Text bleiben auf diesem Mac."),
            String(localized: "Spracherkennung: Parakeet Ultra von moondream auf Basis von NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0), CoreML-Fassung von FluidInference."),
            String(localized: "Sprechertrennung: pyannote community-1 mit WeSpeaker ResNet34 (CC BY 4.0), CoreML-Fassung von FluidInference."),
            String(localized: "FluidAudio und Textnormalisierung von FluidInference (Apache License 2.0)."),
        ]
        return NSAttributedString(
            string: lines.joined(separator: "\n"),
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                // Dynamic color: readable in light and dark mode.
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
    }
}
