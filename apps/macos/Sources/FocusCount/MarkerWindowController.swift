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
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "时间标记"
        window.isReleasedWhenClosed = false
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentMinSize = NSSize(width: 1000, height: 700)
        window.contentView = NSHostingView(rootView: EventHistoryView(store: store, onReturn: { [weak self] in
            self?.window?.performClose(nil)
        }))
        window.center()
        window.setFrameAutosaveName("FocusCountMarkerWindow")
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
