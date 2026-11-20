import BreadcrumbsCore
import SwiftUI

/// What the floating card is showing.
@MainActor
final class NudgeState: ObservableObject {
    enum Mode: Equatable { case hidden, checkIn, answered(worked: Bool), completion }
    @Published var mode: Mode = .hidden
    /// A confetti burst in flight (set on a Yes, cleared when it ends or the panel hides).
    @Published var burst: ConfettiBurst?
}

struct ConfettiBurst: Equatable {
    let start: Date
    /// Snapshot fixtures only: draw this one moment, with no timeline running.
    var frozenAt: Double?
}

/// The floating card: check-in, the brief "answered" beat, and the completion screen.
struct NudgeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nudge: NudgeState
    var close: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let cardWidth: CGFloat = 380
    static let shadowPad: CGFloat = 36

    var body: some View {
        VStack(spacing: 0) {
            if nudge.mode == .hidden {
                // The panel is ordered out but kept alive; render nothing there (a hidden
                // check-in card would otherwise keep a breathing box animating forever).
                Color.clear.frame(width: Self.cardWidth, height: 0)
            } else {
                cardBody
            }
            Spacer(minLength: 0)
        }
        .padding(Self.shadowPad)
    }

    private var cardBody: some View {
        card
            .frame(width: Self.cardWidth)
            .overlay(alignment: .topLeading) {
                if let burst = nudge.burst, !reduceMotion {
                    ConfettiView(burst: burst)
                        .frame(width: Self.cardWidth, height: ConfettiView.height)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.paper)
                    .shadow(color: Theme.shadow, radius: 20, y: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1)
            )
    }

    @ViewBuilder private var card: some View {
        switch nudge.mode {
        case .completion: CompletionCard(model: model, close: close)
        default: CheckInCard(model: model, mode: nudge.mode)
        }
    }
}

struct CheckInCard: View {
    @ObservedObject var model: AppModel
    let mode: NudgeState.Mode

    var body: some View {
        let s = model.sprint ?? model.lastSprint
        let boxes = s?.boxes ?? []
        let total = s?.config.boxes ?? 0
        let answered: Bool? = { if case let .answered(w) = mode { return w } else { return nil } }()
        // While asking, the box being asked about is `currentIndex`; once answered, it's the one before.
        let askedIndex = (s?.currentIndex ?? 0) - (answered == nil ? 0 : 1)
        let isLastBox = answered == nil && model.isLastBoxCheckIn

        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("BOX \(min(answered == nil ? askedIndex + 1 : askedIndex + 2, total)) OF \(total)")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                Text(Format.duration(s?.config.intervalSeconds ?? 0))
                    .font(Theme.ui(11, .medium)).foregroundStyle(Theme.inkSoft)
            }

            BoxRow(boxes: boxes,
                   currentIndex: answered == nil ? askedIndex : s?.currentIndex,
                   currentMode: answered == nil ? .awaiting : model.currentMode,
                   progress: model.progress,
                   maxBoxSize: 38, width: NudgeView.cardWidth - 48)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(headline(answered))
                    .font(Theme.serif(26))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.opacity)
                Text(subline(answered, askedIndex: askedIndex, total: total))
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.inkSoft)
            }

            Group {
                if isLastBox { lastBoxButtons } else { buttons(answered) }
            }
            .background {
                // Plain-letter shortcuts (Return is already the default action). On the last
                // box Y rolls into the next sprint and S ticks it and stops.
                Group {
                    Button("") { model.answer(worked: true, startNext: isLastBox) }.keyboardShortcut("y", modifiers: [])
                    Button("") { model.answer(worked: false) }.keyboardShortcut("n", modifiers: [])
                    if isLastBox {
                        Button("") { model.answer(worked: true) }.keyboardShortcut("s", modifiers: [])
                    }
                }
                .opacity(0)
                .allowsHitTesting(false)
            }
            .disabled(answered != nil)

            if answered == nil {
                globalHints(isLastBox: isLastBox)
            }
        }
        .padding(24)
        .animation(Theme.spring, value: mode)
    }

    private func buttons(_ answered: Bool?) -> some View {
        HStack(spacing: 10) {
            Button { model.answer(worked: true) } label: {
                HStack(spacing: 8) {
                    if answered == true { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                    Text("Yes")
                    if answered == nil { KeyHint(key: "Y", onFill: true) }
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: 40))
            .keyboardShortcut(.defaultAction)
            .opacity(answered == false ? 0 : 1)
            Button { model.answer(worked: false) } label: {
                HStack(spacing: 8) {
                    if answered == false { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                    Text("No")
                    if answered == nil { KeyHint(key: "N") }
                }
            }
            .buttonStyle(SecondaryButtonStyle(height: 40))
            .opacity(answered == true ? 0 : 1)
        }
    }

    /// Last box: the primary action ticks it and rolls straight into the next sprint
    /// (skipping the summary); "Yes, and stop" ticks it and shows the summary.
    private var lastBoxButtons: some View {
        VStack(spacing: 10) {
            Button { model.answer(worked: true, startNext: true) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.forward").font(.system(size: 11, weight: .bold))
                    Text("Yes, start next sprint")
                    KeyHint(key: "Y", onFill: true)
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: 40))
            .keyboardShortcut(.defaultAction)
            HStack(spacing: 10) {
                Button { model.answer(worked: true) } label: {
                    HStack(spacing: 8) {
                        Text("Yes, and stop")
                        KeyHint(key: "S")
                    }
                }
                .buttonStyle(SecondaryButtonStyle(height: 40))
                Button { model.answer(worked: false) } label: {
                    HStack(spacing: 8) {
                        Text("No")
                        KeyHint(key: "N")
                    }
                }
                .buttonStyle(SecondaryButtonStyle(height: 40))
            }
        }
    }

    /// The global shortcuts that answer from any app, without focusing the card first.
    @ViewBuilder private func globalHints(isLastBox: Bool) -> some View {
        let hints = isLastBox
            ? [(CheckInShortcut.yes, "next sprint"), (CheckInShortcut.no, "no"), (CheckInShortcut.stop, "stop")]
            : [(CheckInShortcut.yes, "yes"), (CheckInShortcut.no, "no")]
        let shown = hints.filter { !model.unavailableCheckInHotKeys.contains($0.0) }
        if !shown.isEmpty {
            HStack(spacing: 10) {
                Text("From any app")
                    .foregroundStyle(Theme.inkSoft.opacity(0.8))
                ForEach(shown, id: \.0) { key, label in
                    HStack(spacing: 5) {
                        KeyHint(key: key)
                        Text(label).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            .font(Theme.ui(11))
            .padding(.top, -6)
        }
    }

    private func headline(_ answered: Bool?) -> String {
        switch answered {
        case .some(true): return "Ticked."
        case .some(false): return "Noted."
        case .none: return "Did you work?"
        }
    }

    private func subline(_ answered: Bool?, askedIndex: Int, total: Int) -> String {
        if answered != nil {
            // askedIndex is -1 when "start next sprint" rolled straight into a fresh sprint.
            if askedIndex < 0 { return "Next sprint has started." }
            return askedIndex + 1 < total ? "Box \(askedIndex + 2) has started." : "That was the last box."
        }
        if askedIndex + 1 >= total { return "Last box. Roll straight into the next sprint, or stop here." }
        return "No rush. The next box starts when you answer."
    }
}

struct CompletionCard: View {
    @ObservedObject var model: AppModel
    let close: () -> Void

    var body: some View {
        let s = model.lastSprint ?? model.sprint
        let worked = s?.workedCount ?? 0
        let total = s?.config.boxes ?? 0

        return VStack(alignment: .leading, spacing: 18) {
            Text("Sprint complete.")
                .font(Theme.serif(26))
                .foregroundStyle(Theme.ink)

            BoxRow(boxes: s?.boxes ?? [], maxBoxSize: 38, width: NudgeView.cardWidth - 48, reveal: true)
                .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(worked)").font(Theme.number(44)).foregroundStyle(Theme.ink)
                Text("of \(total) boxes ticked").font(Theme.serif(18)).foregroundStyle(Theme.ink)
            }
            .padding(.bottom, -8)

            Text(message(worked: worked, total: total, interval: s?.config.intervalSeconds ?? 0))
                .font(Theme.ui(12))
                .foregroundStyle(Theme.inkSoft)

            HStack(spacing: 8) {
                BoxView(state: .worked, size: 14)
                Text("Today").font(Theme.ui(12, .medium)).foregroundStyle(Theme.inkSoft)
                Spacer()
                Text(Format.boxes(model.todayWorked)).font(Theme.number(13)).foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.wash))

            HStack(spacing: 10) {
                Button { model.startSprint() } label: { Text("Start another sprint") }
                    .buttonStyle(PrimaryButtonStyle(height: 40))
                    .keyboardShortcut(.defaultAction)
                Button("Done", action: close)
                    .buttonStyle(SecondaryButtonStyle(height: 40))
                    .frame(width: 96)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
    }

    private func message(worked: Int, total: Int, interval: TimeInterval) -> String {
        let real = Format.duration(interval * Double(worked))
        if total > 0 && worked == total { return "Every box ticked. \(real) of real work." }
        if worked == 0 { return "No ticks this time. Showing up still counts." }
        let missed = total - worked
        return "\(real) of real work. \(missed == 1 ? "1 box" : "\(missed) boxes") got away."
    }
}

/// A short, small confetti burst for a Yes. Lives only while `NudgeState.burst` is set (the
/// coordinator clears it after `duration`), so its TimelineView never outlives the burst.
struct ConfettiView: View {
    let burst: ConfettiBurst

    static let duration: Double = 0.95
    static let height: CGFloat = 300
    /// Where the burst comes from, in card coordinates: the top of the Yes button, which in the
    /// answered state always sits in the left half of the button row.
    static let origin = CGPoint(x: 24 + (NudgeView.cardWidth - 58) / 4, y: 188)

    private struct Piece {
        let angle, speed, spin, size: Double
        let round: Bool
        let color: Int
    }

    private static let colors: [Color] = [Theme.tick, Theme.tickPressed, Theme.tick.opacity(0.5), Theme.missed, Theme.missedInk]

    /// Deterministic pieces (a fixed LCG), so every burst and every snapshot looks the same.
    private static let pieces: [Piece] = {
        var seed: UInt64 = 0x9E37_79B9
        func r() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }
        return (0..<32).map { i in
            Piece(angle: -.pi / 2 + (r() - 0.5) * 2.2,   // upward fan, ±63°
                  speed: 240 + r() * 200,
                  spin: (r() - 0.5) * 14,
                  size: 4 + r() * 3.5,
                  round: i % 3 == 0,
                  color: i % colors.count)
        }
    }()

    var body: some View {
        if let t = burst.frozenAt {
            canvas(t)
        } else {
            TimelineView(.animation) { ctx in
                canvas(ctx.date.timeIntervalSince(burst.start))
            }
        }
    }

    private func canvas(_ t: Double) -> some View {
        Canvas { gc, _ in
            guard t >= 0, t < Self.duration else { return }
            let gravity = 760.0
            let drag = 1.0 - min(t, 1) * 0.35
            let fade = t < 0.55 ? 1 : max(0, 1 - (t - 0.55) / (Self.duration - 0.55))
            for p in Self.pieces {
                let x = Self.origin.x + cos(p.angle) * p.speed * t * drag
                let y = Self.origin.y + sin(p.angle) * p.speed * t * drag + 0.5 * gravity * t * t
                var g = gc
                g.opacity = fade
                g.translateBy(x: x, y: y)
                g.rotate(by: .radians(p.spin * t))
                let rect = CGRect(x: -p.size / 2, y: -p.size * 0.3, width: p.size, height: p.size * (p.round ? 1 : 0.6))
                let shape = p.round ? Path(ellipseIn: CGRect(x: -p.size / 2.4, y: -p.size / 2.4, width: p.size / 1.2, height: p.size / 1.2))
                                    : Path(roundedRect: rect, cornerRadius: 1)
                g.fill(shape, with: .color(Self.colors[p.color]))
            }
        }
    }
}
