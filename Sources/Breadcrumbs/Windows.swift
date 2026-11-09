import AppKit
import BreadcrumbsCore
import SwiftUI

final class NudgePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
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

    private func answered(worked: Bool, completed: Bool) {
        dismissWork?.cancel()
        withAnimation(Theme.spring) { nudge.mode = .answered(worked: worked) }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if completed {
                withAnimation(.easeInOut(duration: 0.25)) { self.nudge.mode = .completion }
                self.presentPanel()
            } else if case .answered = self.nudge.mode {
                self.hidePanel()
            }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (completed ? 0.75 : 0.9), execute: work)
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
        let host = NSHostingView(rootView: NudgeView(model: model, nudge: nudge) { [weak self] in self?.closeCompletion() })
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
