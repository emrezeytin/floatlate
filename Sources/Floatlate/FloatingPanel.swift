import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    private static let frameName = "FloatlatePanel"

    init(rootView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 540),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { standardWindowButton($0)?.isHidden = true }
        contentView = NSHostingView(rootView: rootView)

        if !setFrameUsingName(Self.frameName) { center() }
        setFrameAutosaveName(Self.frameName)
    }

    override var canBecomeKey: Bool { true }
}
