import AppKit
import SwiftUI

/// A regular window can move independently; attached sheets cannot.
@MainActor final class MarkerWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MarkerWindowController()

    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(store: StudyStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 810),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "时间标记"
        window.isReleasedWhenClosed = false
        window.isMovable = true
        // Content contains drag handles: only the title bar should move the window.
        window.isMovableByWindowBackground = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentMinSize = NSSize(width: 1000, height: 700)
        window.contentView = NSHostingView(rootView: EventHistoryView(store: store, onReturn: { [weak self] in
            self?.window?.performClose(nil)
        }))
        window.center()
        // Start once with the new 16:9 default, then retain subsequent user resizing.
        window.setFrameAutosaveName("FocusCountMarkerWindowWide")
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
