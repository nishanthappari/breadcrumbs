import BreadcrumbsCore
import SwiftUI

/// What the floating card is showing.
@MainActor
final class NudgeState: ObservableObject {
    enum Mode: Equatable { case hidden, checkIn, answered(worked: Bool), completion }
    @Published var mode: Mode = .hidden
}

/// The floating card: check-in, the brief "answered" beat, and the completion screen.
struct NudgeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nudge: NudgeState
    var close: () -> Void = {}

    static let cardWidth: CGFloat = 380
    static let shadowPad: CGFloat = 36

    var body: some View {
        VStack(spacing: 0) {
            card
                .frame(width: Self.cardWidth)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.paper)
                        .shadow(color: Theme.shadow, radius: 20, y: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1)
                )
            Spacer(minLength: 0)
        }
        .padding(Self.shadowPad)
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
            .background {
                // Plain-letter shortcuts (Return is already the default action).
                Group {
                    Button("") { model.answer(worked: true) }.keyboardShortcut("y", modifiers: [])
                    Button("") { model.answer(worked: false) }.keyboardShortcut("n", modifiers: [])
                }
                .opacity(0)
                .allowsHitTesting(false)
            }
            .disabled(answered != nil)
        }
        .padding(24)
        .animation(Theme.spring, value: mode)
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
            return askedIndex + 1 < total ? "Box \(askedIndex + 2) has started." : "That was the last box."
        }
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
