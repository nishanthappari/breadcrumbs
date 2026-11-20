import AppKit
import BreadcrumbsCore
import SwiftUI

final class NudgePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The panel never takes focus on its own, so its buttons must act on the very first click
/// rather than spending it on making the panel key.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A transparent, click-through window that exists only for the length of one confetti burst,
/// so the burst can fly far past the check-in panel.
@MainActor
final class ConfettiOverlay {
    private var window: NSWindow?
    private var endWork: DispatchWorkItem?

    /// Bursts from `point` (screen coordinates), drawn above windows at `level`.
    func burst(from point: NSPoint, on screen: NSScreen, above level: NSWindow.Level) {
        end()
        // Room for the full spread: ~700pt each side, ~500pt up and ~800pt down for the fall.
        let frame = NSRect(x: point.x - 700, y: point.y - 800, width: 1400, height: 1300)
            .intersection(screen.frame)
        guard !frame.isEmpty else { return }
        let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.level = NSWindow.Level(rawValue: level.rawValue + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        w.identifier = NSUserInterfaceItemIdentifier("confetti")
        let origin = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
        let host = NSHostingView(rootView: ConfettiView(burst: ConfettiBurst(start: Date()), origin: origin))
        host.frame = NSRect(origin: .zero, size: frame.size)
        w.contentView = host
        w.orderFrontRegardless()
        window = w
        let work = DispatchWorkItem { [weak self] in self?.end() }
        endWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ConfettiView.duration + 0.05, execute: work)
    }

    /// Tears the window down; the hosting view and its TimelineView go with it.
    func end() {
        endWork?.cancel()
        endWork = nil
        guard let w = window else { return }
        w.orderOut(nil)
        w.contentView = nil
        window = nil
    }
}

/// Owns the floating check-in / completion card and the History window.
@MainActor
final class WindowCoordinator {
    let model: AppModel
    let nudge = NudgeState()
    private(set) var panel: NudgePanel?
    private(set) var historyWindow: NSWindow?
    private var dismissWork: DispatchWorkItem?

    static let panelSize = NSSize(width: NudgeView.cardWidth + NudgeView.shadowPad * 2, height: 470)

    init(model: AppModel) {
        self.model = model
        model.onIntervalEnded = { [weak self] in self?.showCheckIn() }
        model.onAnswered = { [weak self] worked, completed in self?.answered(worked: worked, completed: completed) }
        model.onSprintStarted = { [weak self] in
            guard let self, self.nudge.mode == .completion else { return }
            self.hidePanel()
        }
        model.onCancelled = { [weak self] in self?.hidePanel() }
    }

    // MARK: Nudge panel

    /// Shows the check-in in front of everything *without* taking keyboard focus, so typing
    /// in another app can never answer it by accident. Click it, or press ⌃⌥B to focus it.
    func showCheckIn(focus: Bool = false) {
        dismissWork?.cancel()
        nudge.mode = .checkIn
        presentPanel(focus: focus)
    }

    /// Brings a pending check-in to the front and gives it the keyboard (hotkey / Raycast).
    func refocus() {
        if model.engine.isAwaitingCheckIn { showCheckIn(focus: true) }
    }

    private let confetti = ConfettiOverlay()
    /// How long the completion card stays before it closes itself (it never has focus, so
    /// Return/Esc can't reach it unless clicked).
    static let completionAutoDismiss: TimeInterval = 6

    private func answered(worked: Bool, completed: Bool) {
        dismissWork?.cancel()
        withAnimation(Theme.spring) { nudge.mode = .answered(worked: worked) }
        if worked { celebrate() }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if completed {
                withAnimation(.easeInOut(duration: 0.25)) { self.nudge.mode = .completion }
                self.presentPanel()
                self.scheduleCompletionDismiss()
            } else if case .answered = self.nudge.mode {
                self.hidePanel()
            }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (completed ? 0.75 : 0.9), execute: work)
    }

    /// A confetti burst on a Yes (any path: buttons, keys, hotkeys, URL scheme), from the Yes
    /// button, in its own short-lived overlay window.
    private func celebrate() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let p = panel, p.isVisible, let screen = p.screen ?? NSScreen.main else { return }
        let point = NSPoint(x: p.frame.minX + NudgeView.yesButtonTop.x,
                            y: p.frame.maxY - NudgeView.yesButtonTop.y)
        confetti.burst(from: point, on: screen, above: p.level)
    }

    /// Closes the completion card by itself after a few seconds, back to idle.
    private func scheduleCompletionDismiss() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.nudge.mode == .completion, self.model.engine.phase == .completed else { return }
            self.closeCompletion()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.completionAutoDismiss, execute: work)
    }

    func closeCompletion() {
        model.dismissCompletion()
        hidePanel()
    }

    private func makePanel() -> NudgePanel {
        let p = NudgePanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.identifier = NSUserInterfaceItemIdentifier("nudge")
        let host = FirstClickHostingView(rootView: NudgeView(model: model, nudge: nudge) { [weak self] in self?.closeCompletion() })
        host.frame = NSRect(origin: .zero, size: Self.panelSize)
        p.contentView = host
        return p
    }

    private func presentPanel(focus: Bool = false) {
        let p = panel ?? makePanel()
        panel = p
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let origin = NSPoint(x: vf.midX - Self.panelSize.width / 2,
                             y: vf.maxY - Self.panelSize.height - 4)
        let target = NSRect(origin: origin, size: Self.panelSize)
        if !p.isVisible {
            p.setFrame(target.offsetBy(dx: 0, dy: 8), display: false)
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                p.animator().alphaValue = 1
                p.animator().setFrame(target, display: true)
            }
        } else {
            p.orderFrontRegardless()
        }
        if focus {
            NSApp.activate(ignoringOtherApps: true)
            p.makeKey()
        }
    }

    func hidePanel() {
        dismissWork?.cancel()
        guard let p = panel, p.isVisible else { nudge.mode = .hidden; return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                p.orderOut(nil)
                if self?.nudge.mode != .checkIn { self?.nudge.mode = .hidden }
                // A check-in may have arrived during the fade.
                if self?.nudge.mode == .checkIn { self?.presentPanel() }
            }
        })
    }

    // MARK: History

    func showHistory() {
        model.refreshStats()
        if historyWindow == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: HistoryView.size),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.title = "Breadcrumbs History"
            w.isReleasedWhenClosed = false
            w.isMovableByWindowBackground = true
            w.identifier = NSUserInterfaceItemIdentifier("history")
            w.contentView = NSHostingView(rootView: HistoryView(model: model))
            w.center()
            historyWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }
}
