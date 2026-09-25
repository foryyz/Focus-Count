import AppKit
import SwiftUI

@MainActor final class FocusAnalysisWindow: NSWindowController, NSWindowDelegate {
    static let shared = FocusAnalysisWindow()
    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(store: StudyStore) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let width = min(1280, screen.width - 40)
        let height = min(width * 9 / 16, screen.height - 60)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "专注分析"
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentMinSize = NSSize(width: 960, height: 600)
        window.contentView = NSHostingView(rootView: FocusAnalysisView(store: store))
        window.center()
        window.setFrameAutosaveName("FocusCountAnalysisWindow")
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { window = nil }
}
