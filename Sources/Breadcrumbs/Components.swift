import BreadcrumbsCore
import SwiftUI

// MARK: - Box

struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.10, y: r.minY + r.height * 0.54))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.minY + r.height * 0.80))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.92, y: r.minY + r.height * 0.20))
        return p
    }
}

/// One notebook box. Animates its own transitions into ticked / missed.
struct BoxView: View {
    enum Mode: Equatable { case still, running, paused, awaiting }

    let state: BoxState
    var mode: Mode = .still
    var progress: Double = 0
    var size: CGFloat = 28

    @State private var checkTrim: CGFloat
    @State private var bounce: CGFloat = 1
    @State private var dashOpacity: Double
    @State private var breathe = false

    init(state: BoxState, mode: Mode = .still, progress: Double = 0, size: CGFloat = 28) {
        self.state = state
        self.mode = mode
        self.progress = progress
        self.size = size
        _checkTrim = State(initialValue: state == .worked ? 1 : 0)
        _dashOpacity = State(initialValue: state == .missed ? 1 : 0)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
    }

    private var isCurrent: Bool { state == .pending && mode != .still }

    var body: some View {
        ZStack {
            shape.fill(fill)
            if isCurrent {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(Theme.live)
                            .frame(height: geo.size.height * (mode == .awaiting ? 1 : progress))
                    }
                }
                .clipShape(shape)
                .opacity(mode == .awaiting ? (breathe ? 1 : 0.55) : 1)
            }
            shape.strokeBorder(border, style: StrokeStyle(lineWidth: max(1.25, size * 0.05),
                                                        dash: mode == .paused && isCurrent ? [size * 0.12, size * 0.1] : []))
            if state == .worked {
                CheckShape()
                    .trim(from: 0, to: checkTrim)
                    .stroke(Theme.tickInk, style: StrokeStyle(lineWidth: max(1.8, size * 0.095), lineCap: .round, lineJoin: .round))
                    .padding(size * 0.25)
            }
            if state == .missed {
                Capsule()
                    .fill(Theme.missedInk)
                    .frame(width: size * 0.34, height: max(1.8, size * 0.08))
                    .opacity(dashOpacity)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(bounce * (mode == .awaiting && isCurrent ? (breathe ? 1.04 : 1) : 1))
        .onChange(of: state) { old, new in
            if new == .worked && old != .worked {
                checkTrim = 0
                withAnimation(.easeOut(duration: 0.35)) { checkTrim = 1 }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { bounce = 1.12 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(Theme.spring) { bounce = 1 }
                }
            } else if new == .missed && old != .missed {
                withAnimation(.easeOut(duration: 0.25)) { dashOpacity = 1 }
            }
        }
        .onAppear { startBreathingIfNeeded() }
        .onChange(of: mode) { _, _ in startBreathingIfNeeded() }
        .animation(.linear(duration: 0.25), value: progress)
        .accessibilityLabel(accessibility)
    }

    private func startBreathingIfNeeded() {
        if mode == .awaiting {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { breathe = true }
        } else {
            breathe = false
        }
    }

    private var fill: Color {
        switch state {
        case .worked: return Theme.tick
        case .missed: return Theme.missed
        case .pending: return Theme.card
        }
    }

    private var border: Color {
        switch state {
        case .worked: return Theme.tick
        case .missed: return Theme.missed
        case .pending: return isCurrent ? Theme.tick : Theme.rule
        }
    }

    private var accessibility: String {
        switch state {
        case .worked: return "Worked"
        case .missed: return "Missed"
        case .pending: return isCurrent ? "Current box" : "Not started"
        }
    }
}

/// A notebook row of boxes on a faint ruled baseline.
struct BoxRow: View {
    let boxes: [BoxState]
    var currentIndex: Int? = nil
    var currentMode: BoxView.Mode = .still
    var progress: Double = 0
    var maxBoxSize: CGFloat = 30
    var width: CGFloat = 288
    var reveal: Bool = false

    @State private var revealed = BoxRow.staticRendering
    /// Set while rendering fixture screenshots, so entrance animations show their end state.
    nonisolated(unsafe) static var staticRendering = false

    var boxSize: CGFloat {
        let n = CGFloat(max(1, boxes.count))
        // spacing = 0.32 × size  →  width = n·s + (n−1)·0.32·s
        return min(maxBoxSize, width / (n + (n - 1) * 0.32))
    }

    var body: some View {
        let s = boxSize
        HStack(spacing: s * 0.32) {
            ForEach(Array(boxes.enumerated()), id: \.offset) { i, state in
                BoxView(state: state,
                        mode: i == currentIndex ? currentMode : .still,
                        progress: i == currentIndex ? progress : 0,
                        size: s)
                    .opacity(reveal && !revealed ? 0 : 1)
                    .scaleEffect(reveal && !revealed ? 0.7 : 1)
                    .animation(reveal ? Theme.spring.delay(Double(i) * 0.06) : nil, value: revealed)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
        .background(alignment: .bottom) {
            // A notebook line running the full content width, just under the boxes.
            Rectangle().fill(Theme.rule).frame(width: width, height: 1)
        }
        .frame(width: width)
        .onAppear { if reveal { DispatchQueue.main.async { revealed = true } } }
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 36
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(13, .semibold))
            .foregroundStyle(Theme.tickInk)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Capsule().fill(configuration.isPressed ? Theme.tickPressed : Theme.tick))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 36
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(13, .medium))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Capsule().fill(configuration.isPressed ? Theme.wash : Theme.card))
            .overlay(Capsule().strokeBorder(Theme.rule, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule())
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(12, .medium))
            .foregroundStyle(configuration.isPressed ? Theme.ink : Theme.inkSoft)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(configuration.isPressed ? Theme.wash : .clear))
            .contentShape(Rectangle())
    }
}

struct KeyHint: View {
    let key: String
    var onFill = false
    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(onFill ? Theme.tickInk.opacity(0.8) : Theme.inkSoft)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(onFill ? Theme.tickInk.opacity(0.35) : Theme.rule, lineWidth: 1))
    }
}

// MARK: - Settings controls

struct ValueStepper: View {
    let value: Int
    let range: ClosedRange<Int>
    let label: (Int) -> String
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: value > range.lowerBound) { onChange(value - 1) }
            Text(label(value))
                .font(Theme.number(13))
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 58)
            stepButton("plus", enabled: value < range.upperBound) { onChange(value + 1) }
        }
        .padding(2)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().strokeBorder(Theme.rule, lineWidth: 1))
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .foregroundStyle(enabled ? Theme.ink : Theme.rule)
                .background(Circle().fill(Theme.wash.opacity(enabled ? 1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .buttonRepeatBehavior(.enabled)
    }
}

struct Chip: View {
    let text: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Theme.number(11, .medium))
                .foregroundStyle(selected ? Theme.tickInk : Theme.ink)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(Capsule().fill(selected ? Theme.tick : Theme.wash))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PillToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { withAnimation(Theme.spring) { isOn.toggle() } } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.tick : Theme.rule).frame(width: 34, height: 20)
                Circle().fill(Theme.card).frame(width: 16, height: 16).padding(2)
                    .shadow(color: Theme.shadow, radius: 1, y: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Week bars

struct WeekBars: View {
    let days: [DayStat]
    var height: CGFloat = 34
    var barWidth: CGFloat = 14
    var showCounts = false
    var labelFont: Font = Theme.ui(9, .medium)

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        return f
    }()

    var body: some View {
        let peak = max(6, days.map(\.total).max() ?? 0)
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                let isToday = i == days.count - 1
                VStack(spacing: 4) {
                    if showCounts {
                        Text(d.worked > 0 ? "\(d.worked)" : "–")
                            .font(Theme.number(11, .semibold))
                            .foregroundStyle(d.worked > 0 ? Theme.ink : Theme.rule)
                    }
                    // One stacked bar per day: missed (sand) under ticked (sage), clipped as one shape.
                    ZStack(alignment: .bottom) {
                        if d.total > 0 {
                            Rectangle().fill(Theme.missed)
                                .frame(height: max(4, height * CGFloat(d.total) / CGFloat(peak)))
                            if d.worked > 0 {
                                Rectangle().fill(Theme.tick)
                                    .frame(height: max(4, height * CGFloat(d.worked) / CGFloat(peak)))
                                    .overlay(alignment: .top) {
                                        if d.missed > 0 { Rectangle().fill(Theme.paper).frame(height: 1) }
                                    }
                            }
                        } else {
                            Rectangle().fill(Theme.rule).frame(height: 3)
                        }
                    }
                    .frame(width: barWidth)
                    .clipShape(RoundedRectangle(cornerRadius: min(barWidth * 0.3, 4), style: .continuous))
                    .frame(width: barWidth, height: height, alignment: .bottom)
                    Text(Self.weekday.string(from: d.day))
                        .font(labelFont)
                        .foregroundStyle(isToday ? Theme.ink : Theme.inkSoft)
                        .fontWeight(isToday ? .bold : .medium)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
