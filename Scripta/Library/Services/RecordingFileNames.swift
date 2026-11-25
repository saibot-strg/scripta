import Foundation

/// Names of a recording's folder and audio files, taken from its title:
/// `Weekly/Weekly.m4a`, meetings also `Weekly (Mikrofon).m4a` and
/// `Weekly (Systemaudio).m4a`. A second recording with the same title gets
/// the folder `Weekly 2`, like a copy in the Finder; its files are named
/// after the folder.
enum RecordingFileNames {
    /// Longest base name in UTF-8 bytes. Volumes allow 255 per name; the
    /// rest is left for " 2", the track suffix and the extension.
    static let maximumBaseLength = 150

    /// The title as a folder name, nil if nothing usable is left.
    ///
    /// "/" and ":" become "-" (":" shows as "/" in the Finder), a time like
    /// "19:51" becomes "19.51" as in the names of macOS screenshots. Line
    /// breaks and other control characters become a space, leading dots are
    /// dropped (they would hide the folder).
    /// - Parameter strict: Also replaces the characters FAT, exFAT and SMB
    ///   volumes reject, and drops trailing dots.
    static func baseName(for title: String, strict: Bool = false) -> String? {
        let forbidden: Set<Character> = strict ? ["/", ":", "\\", "*", "?", "\"", "<", ">", "|"] : ["/", ":"]
        let characters = Array(title)
        var name = ""
        for (index, character) in characters.enumerated() {
            if character == ":", index > 0, index + 1 < characters.count,
               characters[index - 1].isWholeNumber, characters[index + 1].isWholeNumber {
                name.append(".")
            } else if forbidden.contains(character) {
                name.append("-")
            } else if character.isNewline || character.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
                name.append(" ")
            } else {
                name.append(character)
            }
        }
        name = name.trimmingCharacters(in: .whitespaces)
        while name.first == "." || name.first == " " { name.removeFirst() }
        while name.utf8.count > maximumBaseLength { name.removeLast() }
        while name.last == " " || (strict && name.last == ".") { name.removeLast() }
        return name.isEmpty ? nil : name
    }

    /// "Weekly", "Weekly 2", "Weekly 3" … (the first 999).
    static func folderNames(for baseName: String) -> some Sequence<String> {
        (1...999).lazy.map { $0 == 1 ? baseName : "\(baseName) \($0)" }
    }

    /// "Weekly.m4a", "Weekly (Mikrofon).m4a", "Weekly (Systemaudio).m4a".
    static func fileName(for role: TrackRole, folderName: String, pathExtension: String) -> String {
        let stem = switch role {
        case .primary: folderName
        case .microphone: "\(folderName) (\(String(localized: "Mikrofon")))"
        case .system: "\(folderName) (\(String(localized: "Systemaudio")))"
        }
        return pathExtension.isEmpty ? stem : "\(stem).\(pathExtension)"
    }
}
