import SwiftUI

/// Colored rounded-square symbol, as used for rows in System Settings.
struct SourceIcon: View {
    let source: RecordingSource
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: source.systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(source.tint.gradient, in: .rect(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension RecordingSource {
    var tint: Color {
        switch self {
        case .microphone: .red
        case .meeting: .green
        case .importedFile: .blue
        }
    }
}

#Preview {
    HStack {
        ForEach(RecordingSource.allCases, id: \.self) { SourceIcon(source: $0) }
    }
    .padding()
}
