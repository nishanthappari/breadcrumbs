import AppKit
import Combine
import SwiftUI

/// The per-second clock, split out of `AppModel` so a tick only re-renders the few leaf views
/// that show time (the menu bar label and the popover's countdown), not every view that
/// observes the model — several of which live in hidden-but-alive windows.
@MainActor
final class SprintClock: ObservableObject {
    @Published private(set) var now: Date

    init(now: Date = Date()) { self.now = now }

    func set(_ date: Date) {
        if date != now { now = date }
    }
}

// MARK: - Window visibility

private struct WindowIsVisibleKey: EnvironmentKey {
    /// Fail-safe default: anything not inside a tracked window (offscreen renders, the menu bar
    /// label) behaves as visible.
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False while the hosting window is ordered out.
    var windowIsVisible: Bool {
        get { self[WindowIsVisibleKey.self] }
        set { self[WindowIsVisibleKey.self] = newValue }
    }
}

extension View {
    /// Publishes this view's window visibility to descendants as `\.windowIsVisible`.
    func tracksWindowVisibility() -> some View { modifier(WindowVisibilityScope()) }
}

private struct WindowVisibilityScope: ViewModifier {
    @State private var visible = true

    func body(content: Content) -> some View {
        content
            .environment(\.windowIsVisible, visible)
            // Zero-size: it only needs a window, and offscreen ImageRenderer fixtures would
            // otherwise draw their "unsupported NSView" placeholder.
            .background(WindowVisibilityReader { v in if v != visible { visible = v } }.frame(width: 0, height: 0))
    }
}

/// Reports `window.isVisible` whenever it may have changed. Ordering a window in or out posts an
/// occlusion change, so this catches the MenuBarExtra popover closing and reopening.
private struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let v = ReaderView()
        v.onChange = onChange
        return v
    }

    func updateNSView(_ nsView: ReaderView, context: Context) { nsView.onChange = onChange }

    final class ReaderView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let names: [Notification.Name] = [NSWindow.didChangeOcclusionStateNotification,
                                              NSWindow.didBecomeKeyNotification,
                                              NSWindow.willCloseNotification]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        self?.report(closing: note.name == NSWindow.willCloseNotification)
                    }
                }
            }
            // Not during the SwiftUI update that attached us.
            DispatchQueue.main.async { [weak self] in self?.report() }
        }

        private func report(closing: Bool = false) {
            guard let window else { return }
            // Ordered-in is the signal; occlusion is only the trigger. (Occlusion can lag a fade-in
            // from alpha 0, and a false "hidden" would freeze an open countdown.)
            onChange?(!closing && window.isVisible)
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

// MARK: - Live clock leaf

/// Renders `content` with the clock's current time, re-rendering on each clock tick only while
/// its window is visible. When the window comes back it catches up without animating.
struct LiveClock<Content: View>: View {
    let clock: SprintClock
    @ViewBuilder let content: (Date) -> Content

    @Environment(\.windowIsVisible) private var visible
    @State private var shown: Date

    init(clock: SprintClock, @ViewBuilder content: @escaping (Date) -> Content) {
        self.clock = clock
        self.content = content
        _shown = State(initialValue: clock.now)
    }

    var body: some View {
        content(shown)
            .onReceive(clock.$now) { d in
                if visible && d != shown { shown = d }
            }
            .onChange(of: visible) { _, v in
                guard v, clock.now != shown else { return }
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { shown = clock.now }
            }
    }
}
