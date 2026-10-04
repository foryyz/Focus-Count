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
    var resuming = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scenePhase) private var scenePhase
    @State private var hovering = false
    private var colors: [Color] {
        if resuming {
            return [Color(red: 0.78, green: 0.12, blue: 0.26),
                    Color(red: 0.08, green: 0.50, blue: 0.30),
                    Color(red: 0.18, green: 0.32, blue: 0.84),
                    Color(red: 0.78, green: 0.12, blue: 0.26)]
        }
        return [
            Color(red: 0.02, green: 0.58, blue: 0.76),
            Color(red: 0.23, green: 0.32, blue: 0.94),
            Color(red: 0.57, green: 0.20, blue: 0.88),
            Color(red: 0.90, green: 0.18, blue: 0.52),
            Color(red: 0.96, green: 0.47, blue: 0.26),
            Color(red: 0.57, green: 0.20, blue: 0.88)
        ]
    }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 32).padding(.vertical, 15)
            .foregroundStyle(.white)
            .background {
                TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || !isEnabled || scenePhase != .active)) { context in
                    let progress = reduceMotion || !isEnabled ? 0.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 7) / 7
                    let angle = progress * 2 * Double.pi
                    let start = resuming ? UnitPoint(x: 0.5 + 0.5 * cos(angle), y: 0.5 + 0.5 * sin(angle)) : UnitPoint(x: 0.5 + 0.5 * cos(angle), y: 0.5 + 0.35 * sin(angle))
                    let end = resuming ? UnitPoint(x: 0.5 - 0.5 * cos(angle), y: 0.5 - 0.5 * sin(angle)) : UnitPoint(x: 0.5 - 0.5 * cos(angle), y: 0.5 - 0.35 * sin(angle))
                    Capsule().fill(LinearGradient(colors: colors, startPoint: start, endPoint: end))
                        .overlay {
                            if !resuming {
                                GeometryReader { geometry in
                                    Ellipse()
                                        .fill(Color.cyan.opacity(0.55))
                                        .frame(width: geometry.size.width * 0.65, height: geometry.size.height * 1.5)
                                        .blur(radius: 18)
                                        .offset(x: geometry.size.width * (0.15 + 0.3 * sin(angle)), y: -geometry.size.height * 0.75)
                                    Ellipse()
                                        .fill(Color.pink.opacity(0.5))
                                        .frame(width: geometry.size.width * 0.55, height: geometry.size.height)
                                        .blur(radius: 16)
                                        .offset(x: geometry.size.width * (0.35 - 0.3 * sin(angle)), y: geometry.size.height * 0.55)
                                }.clipShape(Capsule())
                            }
                        }
                        .overlay {
                            if !resuming {
                                Capsule().fill(LinearGradient(colors: [.white.opacity(0.24), .clear, .black.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                            }
                        }
                        .overlay {
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(LinearGradient(colors: [.clear, .white.opacity(resuming ? 0.28 : 0.4), .clear], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geometry.size.width * 0.55)
                                    .rotationEffect(.degrees(20))
                                    .offset(x: geometry.size.width * (progress * 2.2 - 0.7))
                            }.clipShape(Capsule())
                        }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.15), .white.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: colors[2].opacity(isEnabled ? (hovering ? 0.28 : 0.17) : 0), radius: hovering ? 13 : 9, y: 4)
            .shadow(color: resuming || !isEnabled ? .clear : colors[0].opacity(hovering ? 0.3 : 0.18), radius: hovering ? 17 : 12, x: -5, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : (hovering && !resuming && isEnabled ? 1.025 : 1))
            .opacity(isEnabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hovering)
            .onHover { hovering = $0 }
    }
}
