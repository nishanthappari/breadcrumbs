import AppKit
import BreadcrumbsCore
import SwiftUI

// MARK: - Menu bar label

/// A tiny template glyph that mirrors the current box: outline when idle, a rising fill while
/// running, dashed when paused, solid while a check-in waits.
enum MenuBarGlyph {
    enum Kind: Hashable { case idle, running(Int), paused, awaiting }

    private static var cache: [Kind: NSImage] = [:]

    static func image(for kind: Kind) -> NSImage {
        if let img = cache[kind] { return img }
        let size = NSSize(width: 15, height: 15)
        let img = NSImage(size: size, flipped: false) { _ in
            let rect = NSRect(x: 1.5, y: 1.5, width: 12, height: 12)
            let path = NSBezierPath(roundedRect: rect, xRadius: 3.4, yRadius: 3.4)
            NSColor.black.setStroke()
            NSColor.black.setFill()
            path.lineWidth = 1.5
            switch kind {
            case .idle:
                path.stroke()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: 4.6, y: 7.6))
                check.line(to: NSPoint(x: 6.7, y: 5.3))
                check.line(to: NSPoint(x: 10.6, y: 10.0))
                check.lineWidth = 1.6
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.stroke()
            case let .running(eighths):
                path.stroke()
                let h = 12 * CGFloat(eighths) / 8
                if h > 0 {
                    NSGraphicsContext.saveGraphicsState()
                    path.addClip()
                    NSRect(x: 1.5, y: 1.5, width: 12, height: h).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
            case .paused:
                path.stroke()
                NSRect(x: 5.4, y: 5, width: 1.5, height: 5).fill()
                NSRect(x: 8.1, y: 5, width: 1.5, height: 5).fill()
            case .awaiting:
                path.stroke()
                NSBezierPath(ovalIn: NSRect(x: 5.5, y: 5.5, width: 4, height: 4)).fill()
            }
            return true
        }
        img.isTemplate = true
        cache[kind] = img
        return img
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarGlyph.image(for: glyphKind))
            Text(model.menuBarText).monospacedDigit()
        }
    }

    private var glyphKind: MenuBarGlyph.Kind {
        switch model.engine.phase {
        case .running: return .running(Int((model.progress * 8).rounded(.down)))
        case .paused: return .paused
        case .awaitingCheckIn: return .awaiting
        default: return .idle
        }
    }
}

// MARK: - Popover

struct MenuContentView: View {
    @ObservedObject var model: AppModel
    var openHistory: () -> Void = {}
    var quit: () -> Void = { NSApp.terminate(nil) }
    @State var page: Page = .main

    enum Page { case main, settings }

    static let width: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch page {
            case .main: mainPage
            case .settings: SettingsPage(model: model) { withAnimation(Theme.spring) { page = .main } }
            }
        }
        .frame(width: Self.width)
        .background(Theme.paper)
    }

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            stateBlock
            Rectangle().fill(Theme.rule).frame(height: 1)
            Button(action: openHistory) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This week").font(Theme.ui(11, .medium)).foregroundStyle(Theme.inkSoft)
                        Text("\(model.week.map(\.worked).reduce(0, +))")
                            .font(Theme.number(20)).foregroundStyle(Theme.ink)
                        Text("boxes ticked").font(Theme.ui(10)).foregroundStyle(Theme.inkSoft)
                    }
                    .frame(width: 78, alignment: .leading)
                    WeekBars(days: model.week, height: 30, barWidth: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            footer
        }
        .padding(16)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Breadcrumbs").font(Theme.serif(16, .semibold)).foregroundStyle(Theme.ink)
            Spacer()
            HStack(spacing: 5) {
                BoxView(state: .worked, size: 11)
                Text("\(model.todayWorked) today").font(Theme.number(12, .medium)).foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.wash))
        }
    }

    @ViewBuilder private var stateBlock: some View {
        switch model.engine.phase {
        case .idle, .completed: idleBlock
        case .running, .paused: runningBlock
        case .awaitingCheckIn: checkInBlock
        }
    }

    private var idleBlock: some View {
        let cfg = model.nextConfig
        return VStack(alignment: .leading, spacing: 14) {
            BoxRow(boxes: model.lastSprint?.boxes ?? Array(repeating: .pending, count: cfg.boxes),
                   maxBoxSize: 34, width: Self.width - 32)
                .frame(maxWidth: .infinity)
            HStack {
                if let last = model.lastSprint, model.engine.phase == .completed || model.lastSprint != nil {
                    Text("Last sprint: \(last.workedCount) of \(last.config.boxes)")
                } else {
                    Text("\(cfg.boxes) × \(Format.duration(cfg.intervalSeconds))")
                }
                Spacer()
                Text(Format.duration(cfg.intervalSeconds * Double(cfg.boxes)))
            }
            .font(Theme.ui(11, .medium))
            .foregroundStyle(Theme.inkSoft)
            Button { model.startSprint() } label: {
                HStack(spacing: 8) {
                    Text("Start sprint")
                    KeyHint(key: HotKey.displayString, onFill: true)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var runningBlock: some View {
        let s = model.sprint!
        let paused = model.engine.isPaused
        return VStack(alignment: .leading, spacing: 14) {
            BoxRow(boxes: s.boxes, currentIndex: s.currentIndex, currentMode: model.currentMode,
                   progress: model.progress, maxBoxSize: 34, width: Self.width - 32)
                .frame(maxWidth: .infinity)
            HStack(alignment: .lastTextBaseline) {
                Text(Format.clock(model.remaining ?? 0))
                    .font(Theme.number(30, .medium))
                    .foregroundStyle(paused ? Theme.inkSoft : Theme.ink)
                    .contentTransition(.numericText(countsDown: true))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Box \(s.currentIndex + 1) of \(s.config.boxes)")
                        .font(Theme.ui(12, .semibold)).foregroundStyle(Theme.ink)
                    Text(paused ? "Paused" : "\(Format.duration(s.config.intervalSeconds)) each")
                        .font(Theme.ui(11)).foregroundStyle(Theme.inkSoft)
                }
            }
            HStack(spacing: 8) {
                Button { model.togglePause() } label: {
                    Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(SecondaryButtonStyle(height: 32))
                Button { model.cancel() } label: { Text("Cancel sprint") }
                    .buttonStyle(SecondaryButtonStyle(height: 32))
            }
        }
    }

    private var checkInBlock: some View {
        let s = model.sprint!
        return VStack(alignment: .leading, spacing: 14) {
            BoxRow(boxes: s.boxes, currentIndex: s.currentIndex, currentMode: .awaiting, maxBoxSize: 34, width: Self.width - 32)
                .frame(maxWidth: .infinity)
            HStack(alignment: .firstTextBaseline) {
                Text("Did you work?").font(Theme.serif(20)).foregroundStyle(Theme.ink)
                Spacer()
                Text("Box \(s.currentIndex + 1) of \(s.config.boxes)")
                    .font(Theme.ui(11, .medium)).foregroundStyle(Theme.inkSoft)
            }
            HStack(spacing: 8) {
                Button("Yes") { model.answer(worked: true) }.buttonStyle(PrimaryButtonStyle(height: 32))
                Button("No") { model.answer(worked: false) }.buttonStyle(SecondaryButtonStyle(height: 32))
            }
            Button { model.cancel() } label: { Text("Cancel sprint") }
                .buttonStyle(QuietButtonStyle())
                .frame(maxWidth: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Button(action: openHistory) { Label("History", systemImage: "chart.bar") }
            Button { withAnimation(Theme.spring) { page = .settings } } label: { Label("Settings", systemImage: "slider.horizontal.3") }
            Spacer()
            Button(action: quit) { Text("Quit") }
        }
        .buttonStyle(QuietButtonStyle())
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, -6)
    }
}

struct SettingsPage: View {
    @ObservedObject var model: AppModel
    let back: () -> Void

    private let presets = [5, 10, 15, 25, 30, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(QuietButtonStyle())
                Text("Settings").font(Theme.serif(16, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.leading, -6)

            VStack(alignment: .leading, spacing: 10) {
                row("Interval", detail: "Minutes per box") {
                    ValueStepper(value: model.intervalMinutes, range: SettingsStore.intervalRange,
                                 label: { "\($0) min" }, onChange: model.setInterval)
                }
                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { m in
                        Chip(text: "\(m)", selected: model.intervalMinutes == m) { model.setInterval(m) }
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            row("Boxes per sprint", detail: nil) {
                ValueStepper(value: model.boxesPerSprint, range: SettingsStore.boxesRange,
                             label: { "\($0)" }, onChange: model.setBoxes)
            }

            BoxRow(boxes: Array(repeating: .pending, count: model.boxesPerSprint), maxBoxSize: 22,
                   width: MenuContentView.width - 32)
                .frame(maxWidth: .infinity)
            Text("A sprint is \(Format.boxes(model.boxesPerSprint)) × \(model.intervalMinutes) min = \(Format.duration(Double(model.intervalMinutes * model.boxesPerSprint * 60))).")
                .font(Theme.ui(11)).foregroundStyle(Theme.inkSoft)

            Rectangle().fill(Theme.rule).frame(height: 1)

            row("Open at login", detail: nil) {
                PillToggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            }
            row("Start shortcut", detail: nil) { KeyHint(key: HotKey.displayString) }

            HStack {
                Button("Reset to 5 min × 6") { model.resetSettings() }.buttonStyle(QuietButtonStyle())
                Spacer()
                Text("Stored on this Mac only").font(Theme.ui(10)).foregroundStyle(Theme.inkSoft)
            }
            .padding(.leading, -6)
        }
        .padding(16)
    }

    private func row<C: View>(_ title: String, detail: String?, @ViewBuilder control: () -> C) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.ui(13, .medium)).foregroundStyle(Theme.ink)
                if let detail { Text(detail).font(Theme.ui(10)).foregroundStyle(Theme.inkSoft) }
            }
            Spacer()
            control()
        }
    }
}
