import CoreTransferable
import Foundation

/// What can be dropped on a folder: a recording from the list (its ID as
/// text) or a file from the Finder.
enum LibraryDrop: Transferable {
    case recording(UUID)
    case file(URL)

    var recordingID: UUID? {
        if case .recording(let id) = self { id } else { nil }
    }

    var fileURL: URL? {
        if case .file(let url) = self { url } else { nil }
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(importing: { (url: URL) in LibraryDrop.file(url) })
        ProxyRepresentation(importing: { (text: String) in
            guard let id = UUID(uuidString: text) else { throw CocoaError(.fileReadCorruptFile) }
            return LibraryDrop.recording(id)
        })
    }
}
