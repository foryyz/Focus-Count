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
    var tint: Color = .teal
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
                    canvas.stroke(path, with: .color(tint.opacity(running ? 0.48 - Double(line) * 0.12 : 0.32 - Double(line) * 0.07)), lineWidth: line == 0 ? 2 : 1)
                }
            }
        }.frame(height: 54).accessibilityHidden(true).allowsHitTesting(false)
    }
}

/// A compact foil-like finish; the label stays still and readable as light passes behind it.
struct PrismaticStartStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    private let colors = [
        Color(red: 0.12, green: 0.48, blue: 0.57),
        Color(red: 0.25, green: 0.39, blue: 0.75),
        Color(red: 0.53, green: 0.32, blue: 0.72),
        Color(red: 0.69, green: 0.32, blue: 0.49),
        Color(red: 0.64, green: 0.43, blue: 0.20)
    ]
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 32).padding(.vertical, 15)
            .foregroundStyle(.white)
            .background {
                TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || !isEnabled)) { context in
                    let progress = reduceMotion || !isEnabled ? 0.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 7) / 7
                    Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .overlay {
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geometry.size.width * 0.55)
                                    .rotationEffect(.degrees(20))
                                    .offset(x: geometry.size.width * (progress * 2.2 - 0.7))
                            }.clipShape(Capsule())
                        }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.15), .white.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: colors[2].opacity(isEnabled ? (hovering ? 0.28 : 0.17) : 0), radius: hovering ? 13 : 9, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hovering)
            .onHover { hovering = $0 }
    }
}
