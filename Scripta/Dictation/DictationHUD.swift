import AppKit
import SwiftUI

/// Floating pill near the bottom of the screen while dictating. A
/// non-activating panel that never becomes key, so the text field the user
/// is typing into keeps its focus.
@MainActor
final class DictationHUD {
    private var panel: HUDPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ controller: DictationController) {
        hideTask?.cancel()
        let panel = panel ?? HUDPanel(rootView: DictationHUDView(controller: controller))
        self.panel = panel
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func hide(after delay: Duration = .zero, completion: @escaping @MainActor () -> Void = {}) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let panel = self?.panel else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
            completion()
        }
    }

    /// Bottom center of the screen with the mouse pointer, above the Dock.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 48))
    }
}

private final class HUDPanel: NSPanel {
    init(rootView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = NSHostingView(rootView: rootView)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct DictationHUDView: View {
    let controller: DictationController

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 16)
        .frame(width: 280, height: 46)
        .glassEffect(.regular, in: .capsule)
        .frame(width: 300, height: 64)
        .animation(.smooth(duration: 0.2), value: controller.phase)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .idle:
            EmptyView()
        case .recording:
            Image(systemName: "mic.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating)
            LevelMeterView(levels: controller.levels, tint: .red)
                .frame(height: 22)
        case .transcribing:
            ProgressView().controlSize(.small)
            Text("Wird erkannt …")
            Spacer(minLength: 0)
        case .finished(let result):
            Image(systemName: result.symbol)
                .foregroundStyle(result.isSuccess ? .green : .orange)
            Text(result.message)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }
}

extension TextInserter.Result {
    var isSuccess: Bool { self == .inserted || self == .pasted }

    var symbol: String {
        isSuccess ? "checkmark.circle.fill" : "doc.on.clipboard"
    }

    var message: String {
        switch self {
        case .inserted, .pasted:
            String(localized: "Eingefügt")
        case .copiedToClipboard:
            String(localized: "In der Zwischenablage – zum Einfügen ⌘V drücken")
        case .blockedBySecureInput:
            String(localized: "Passwortfeld aktiv – Text liegt in der Zwischenablage")
        }
    }
}
