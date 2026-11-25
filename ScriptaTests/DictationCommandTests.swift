import AVFoundation
import Foundation
import Testing
@testable import Scripta

/// Spoken commands with the real model. Audio: `say` (DE: Anna, EN: Samantha)
/// dictating sentences with the commands spoken as words.
@MainActor
@Suite("Dictation commands end to end", .enabled(if: ParakeetEngine.isModelInstalled), .serialized)
struct DictationCommandEndToEndTests {
    private func dictate(_ resource: String) async throws -> String {
        let url = try #require(Bundle(for: CommandToken.self).url(forResource: resource, withExtension: "m4a"))
        let file = try AVAudioFile(forReading: url)
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: input)
        let buffer = DictationAudioBuffer()
        buffer.append(input)
        let library = LibraryService(modelContext: ModelContainerFactory.makeInMemory().mainContext,
                                     storage: RecordingStorage(rootURL: TestAudio.temporaryDirectory()))
        return try await TranscriptionService(library: library).dictate(samples: buffer.finish())
    }

    @Test("German commands spoken with short pauses")
    func german() async throws {
        let text = try await dictate("dictation-commands-de")
        #expect(DictationCommands.apply(to: text)
            == "Hallo Tobias, wie geht es dir? Ich hoffe gut.\nBis morgen!\n\nDie Liste: Äpfel, Birnen. Das ist super!",
            "raw: \(text)")
    }

    @Test("English commands spoken with short pauses")
    func english() async throws {
        let text = try await dictate("dictation-commands-en")
        // "comma" said on its own is sometimes heard as "Kana"; the rest must be right.
        let result = DictationCommands.apply(to: text)
        #expect(result.contains("how are you? I hope you are well.\nSee you tomorrow!\n\nThe list: apples"), "raw: \(text) → \(result)")
        #expect(result.hasSuffix("ears."), "\(result)")
    }
}

@Suite("Dictation commands")
struct DictationCommandTests {
    @Test("Parakeet output with short pauses (German)")
    func germanWithPauses() {
        let raw = "Hallo Tobias, wie geht es dir? Fragezeichen, ich hoffe gut, Punkt, neue Zeile, bis morgen, Ausrufezeichen, neuer Absatz, die Liste, Doppelpunkt, Äpfel, Komma, Birnen, Punkt, das ist super, Rufzeichen."
        #expect(DictationCommands.apply(to: raw)
            == "Hallo Tobias, wie geht es dir? Ich hoffe gut.\nBis morgen!\n\nDie Liste: Äpfel, Birnen. Das ist super!")
    }

    @Test("Parakeet output with short pauses (English)")
    func englishWithPauses() {
        let raw = "Hi Tobias, comma, how are you? Question mark. I hope you are well. Period. New line. See you tomorrow. Exclamation mark. New paragraph. The list. Colon. Apples. Comma. Pears. Full stop."
        #expect(DictationCommands.apply(to: raw)
            == "Hi Tobias, how are you? I hope you are well.\nSee you tomorrow!\n\nThe list: apples, pears.")
    }

    @Test("Parakeet output without pauses: commands half converted, some glued to words")
    func germanFluent() {
        let raw = "Hallo Tobias, wie geht es dir? Fragezeichen, ich hoffe gut.neue Zeile bis morgen Ausrufezeichen neuer Absatz, die Liste Doppelpunktäpfel, Birnenpunkt, das ist super Rufzeichen."
        #expect(DictationCommands.apply(to: raw)
            == "Hallo Tobias, wie geht es dir? Ich hoffe gut.\nBis morgen!\n\nDie Liste Doppelpunktäpfel, Birnenpunkt, das ist super!")
    }

    @Test("Ordinary words stay words", arguments: [
        "Der Punkt ist, dass wir auf den Punkt kommen.",
        "Das ist ein guter Zeitpunkt, die Punkte zu zählen.",
        "Im zweiten Absatz steht es.",
        "It lasted for a period of time.",
        "The colon is part of the gut.",
        "Use a dash of salt.",
    ])
    func ordinaryWords(sentence: String) {
        #expect(DictationCommands.apply(to: sentence) == sentence)
    }

    @Test("A lone 'Punkt' or 'period' at the end is a command")
    func loneAmbiguousWords() {
        #expect(DictationCommands.apply(to: "Das war's. Punkt.") == "Das war's.")
        #expect(DictationCommands.apply(to: "That's it. Period.") == "That's it.")
        #expect(DictationCommands.apply(to: "Das war's, Absatz, und weiter") == "Das war's\n\nUnd weiter")
    }

    @Test("Between digits no space is added")
    func digits() {
        #expect(DictationCommands.apply(to: "3 Komma 5 Prozent") == "3,5 Prozent")
        #expect(DictationCommands.apply(to: "Version 2 Punkt 1") == "Version 2.1")
    }

    @Test("Brackets, quotes, hyphen and dash")
    func pairsAndJoins() {
        #expect(DictationCommands.apply(to: "Das ist Klammer auf wichtig Klammer zu gut") == "Das ist (wichtig) gut")
        #expect(DictationCommands.apply(to: "Er sagte, Anführungszeichen auf, Hallo, Anführungszeichen zu.") == "Er sagte „Hallo“")
        #expect(DictationCommands.apply(to: "Schick mir eine E Bindestrich Mail") == "Schick mir eine E-Mail")
        #expect(DictationCommands.apply(to: "gut, Gedankenstrich, aber teuer") == "gut – aber teuer")
        #expect(DictationCommands.apply(to: "He said open quote hello close quote") == "He said “hello”")
    }

    @Test("English keeps 'I' capitalized after a spoken comma")
    func englishI() {
        #expect(DictationCommands.apply(to: "Well. Comma. I think so.") == "Well, I think so.")
    }

    @Test("Commands are found in any letter case, with several spaces")
    func caseAndSpacing() {
        #expect(DictationCommands.apply(to: "hallo NEUE   zeile welt") == "hallo\nWelt")
    }

    @Test("A dictation ending with a line break gets no trailing space; commands can be switched off")
    func formatting() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: DictationSettings.appendsSpaceKey)
        defaults.removeObject(forKey: DictationSettings.usesVoiceCommandsKey)
        #expect(DictationController.format("Hallo, neue Zeile.") == "Hallo\n")
        #expect(DictationController.format("Hallo, Punkt.") == "Hallo. ")
        defaults.set(false, forKey: DictationSettings.usesVoiceCommandsKey)
        defer { defaults.removeObject(forKey: DictationSettings.usesVoiceCommandsKey) }
        #expect(DictationController.format("Hallo, neue Zeile.") == "Hallo, neue Zeile. ")
    }
}

private final class CommandToken {}
