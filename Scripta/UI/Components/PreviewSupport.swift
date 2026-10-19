#if DEBUG
import SwiftData
import SwiftUI

/// Preview environment with an in-memory library filled with sample data.
struct SampleLibraryPreview: PreviewModifier {
    static func makeSharedContext() async throws -> AppModel {
        let container = ModelContainerFactory.makeInMemory()
        let model = AppModel(library: LibraryService(modelContext: container.mainContext))
        try model.library.insertSampleData()
        return model
    }

    func body(content: Content, context: AppModel) -> some View {
        content
            .environment(context)
            .modelContext(context.library.modelContext)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    @MainActor static var sampleLibrary: Self { .modifier(SampleLibraryPreview()) }
}

extension SampleData {
    /// First meeting recording of the sample library (for detail previews).
    static func firstMeeting(in context: ModelContext) -> Recording {
        let meeting = RecordingSource.meeting.rawValue
        let descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.sourceRaw == meeting })
        guard let recording = try? context.fetch(descriptor).first else {
            preconditionFailure("Sample data contains no meeting")
        }
        return recording
    }
}
#endif
