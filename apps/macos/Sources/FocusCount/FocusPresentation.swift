import SwiftUI
import AppKit

/// Only observes the window hosting this view, including native full-screen transitions.
@MainActor final class FocusWindow: ObservableObject {
    weak var window: NSWindow?
    @Published var fullScreen = false
    private var observers: [NSObjectProtocol] = []
    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        self.window = window
        window.collectionBehavior.insert(.fullScreenPrimary)
        fullScreen = window.styleMask.contains(.fullScreen)
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fullScreen = window.styleMask.contains(.fullScreen) }
            })
        }
    }
    func toggle() { window?.toggleFullScreen(nil) }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

struct FocusWindowReader: NSViewRepresentable {
    let controller: FocusWindow
    func makeNSView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.onWindow = { controller.attach($0) }
        return view
    }
    func updateNSView(_ view: WindowProbe, context: Context) {}
    final class WindowProbe: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { DispatchQueue.main.async { [weak self] in self?.onWindow?(window) } }
        }
    }
}

/// Ambient waves communicate a running timer, not progress toward a target.
struct FocusFlow: View {
    let running: Bool
    let reduceMotion: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !running || reduceMotion)) { context in
            Canvas { canvas, size in
                let t = running && !reduceMotion ? context.date.timeIntervalSinceReferenceDate : 0
                for line in 0..<3 {
                    var path = Path()
                    for step in 0...100 {
                        let x = size.width * Double(step) / 100
                        let envelope = sin(Double(step) / 100 * .pi)
                        let y = size.height / 2 + sin(Double(step) / 100 * .pi * 3 - t * 0.65 + Double(line) * 0.8) * 14 * envelope
                        if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    canvas.stroke(path, with: .color(.teal.opacity(running ? 0.48 - Double(line) * 0.12 : 0.15)), lineWidth: line == 0 ? 2 : 1)
                }
            }
        }.frame(height: 54).accessibilityHidden(true).allowsHitTesting(false)
    }
}
