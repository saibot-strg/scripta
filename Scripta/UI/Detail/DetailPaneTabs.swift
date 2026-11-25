import SwiftUI

/// Transcript or summary, as two quiet text tabs: the chosen one is bold and
/// underlined, nothing is filled.
struct DetailPaneTabs: View {
    @Binding var selection: DetailPane

    var body: some View {
        HStack(spacing: 22) {
            ForEach(DetailPane.allCases) { pane in
                let isSelected = pane == selection
                Button {
                    selection = pane
                } label: {
                    Text(pane.label)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .padding(.bottom, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(isSelected ? Color.accentColor : .clear)
                                .frame(height: 2)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Ansicht"))
    }
}
