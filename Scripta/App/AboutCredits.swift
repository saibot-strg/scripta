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
            String(localized: "Titel und Zusammenfassungen (optional): Apple Intelligence oder Qwen 3.5 (Alibaba Cloud), Ministral 3 (Mistral AI) und Gemma 4 (Google), jeweils Apache License 2.0."),
            String(localized: "MLX und mlx-swift-lm von ml-explore, llama.cpp von ggml.org und llama.swift von Mattt (MIT); swift-transformers und swift-jinja von Hugging Face (Apache License 2.0)."),
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
