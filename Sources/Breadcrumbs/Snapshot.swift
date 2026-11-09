import AppKit
import BreadcrumbsCore
import SwiftUI

enum PNG {
    /// Renders a SwiftUI view with the given appearance at 2×.
    @MainActor
    static func render<V: View>(_ view: V, dark: Bool, to url: URL) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var out: Data?
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, dark ? .dark : .light))
            renderer.scale = 2
            if let cg = renderer.cgImage {
                out = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
            }
        }
        if let out { try? out.write(to: url) } else { NSLog("Breadcrumbs: render failed for \(url.lastPathComponent)") }
    }
}

/// Offscreen renders of every state from fixtures, light and dark: `Breadcrumbs --snapshot <dir>`.
@MainActor
enum FixtureSnapshots {
    static func run(dir: String) {
        BoxRow.staticRendering = true
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("breadcrumbs-fixture-\(UUID().uuidString)")
        let history = HistoryStore(fileURL: tmp.appendingPathComponent("history.json"))
        seed(history)
        let defaults = UserDefaults(suiteName: "breadcrumbs.fixture.\(UUID().uuidString)")!
        let model = AppModel(settings: SettingsStore(defaults: defaults), history: history, chime: nil, statusURL: nil)

        let t0 = Date()
        let cfg = SprintConfig(intervalSeconds: 300, boxes: 6)

        func engine(_ answers: [Bool], then: (inout SprintEngine, Date) -> Void = { _, _ in }) -> (SprintEngine, Date) {
            var e = SprintEngine()
            var t = t0
            e.start(config: cfg, now: t)
            for a in answers { t += 300; e.tick(now: t); e.answer(worked: a, now: t) }
            then(&e, t)
            return (e, t)
        }

        func both(_ name: String, _ view: () -> some View) {
            for dark in [false, true] {
                PNG.render(view(), dark: dark, to: base.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }

        let popover = { (page: MenuContentView.Page) in
            MenuContentView(model: model, page: page).fixedSize()
        }

        // Idle
        model.debugLoad(engine: SprintEngine(), now: t0)
        both("01-popover-idle") { popover(.main) }
        both("02-menubar-idle") { menuBarStrip(model) }

        // Running: box 3 of 6, 2:41 left
        let (run, tr) = engine([true, false])
        model.debugLoad(engine: run, now: tr + 139)
        both("03-popover-running") { popover(.main) }
        both("04-menubar-running") { menuBarStrip(model) }

        // Paused
        var paused = run
        paused.pause(now: tr + 139)
        model.debugLoad(engine: paused, now: tr + 139)
        both("05-popover-paused") { popover(.main) }
        both("06-menubar-paused") { menuBarStrip(model) }

        // Check-in on box 3
        var ask = run
        ask.tick(now: tr + 300)
        model.debugLoad(engine: ask, now: tr + 300)
        both("07-checkin") { panel(model, .checkIn) }
        both("08-popover-checkin") { popover(.main) }
        both("09-menubar-checkin") { menuBarStrip(model) }

        // Just answered yes on box 3 (box 4 started)
        var answered = ask
        answered.answer(worked: true, now: tr + 300)
        model.debugLoad(engine: answered, now: tr + 301)
        both("10-checkin-answered") { panel(model, .answered(worked: true)) }

        // Completed 5 of 6
        let (done, td) = engine([true, false, true, true, true, true])
        model.debugLoad(engine: done, now: td, lastSprint: done.sprint)
        both("11-completion") { panel(model, .completion) }

        // History + settings
        model.debugLoad(engine: SprintEngine(), now: t0)
        both("12-history") { HistoryView(model: model) }
        both("13-popover-settings") { popover(.settings) }

        try? FileManager.default.removeItem(at: tmp)
        print("Rendered fixtures to \(base.path)")
    }

    static func panel(_ model: AppModel, _ mode: NudgeState.Mode) -> some View {
        let nudge = NudgeState()
        nudge.mode = mode
        return NudgeView(model: model, nudge: nudge).frame(width: WindowCoordinator.panelSize.width).fixedSize()
            .background(Color(nsColor: .dynamic(0xDCD8CF, 0x3A3A3C)))
    }

    static func menuBarStrip(_ model: AppModel) -> some View {
        HStack(spacing: 14) {
            Spacer()
            Image(systemName: "wifi").font(.system(size: 13, weight: .semibold))
            MenuBarLabel(model: model).font(.system(size: 13, weight: .medium))
            Image(systemName: "battery.75").font(.system(size: 14))
            Text("Mon 9 Nov  10:42").font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(Color(nsColor: .dynamic(0x1D1D1F, 0xF5F5F7)))
        .padding(.horizontal, 12)
        .frame(width: 420, height: 28)
        .background(Color(nsColor: .dynamic(0xEDEBE6, 0x2A2A2C)))
    }

    private static func seed(_ h: HistoryStore) {
        let cal = Calendar.current
        let pattern: [(Int, Int)] = [(9, 3), (14, 4), (6, 0), (11, 1), (17, 1), (4, 2), (0, 0)]
        let sid = UUID()
        for (i, (w, m)) in pattern.enumerated() {
            let day = cal.date(byAdding: .day, value: i - 6, to: cal.startOfDay(for: Date()))!.addingTimeInterval(10 * 3600)
            for k in 0..<(w + m) {
                try? h.append(BoxRecord(timestamp: day.addingTimeInterval(Double(k) * 300), worked: k < w,
                                        sprintID: sid, boxIndex: k % 6, intervalSeconds: 300))
            }
        }
        // Today: 12 ticked, 2 missed.
        for k in 0..<14 {
            try? h.append(BoxRecord(timestamp: Date().addingTimeInterval(-Double(k) * 300 - 60), worked: k >= 2,
                                    sprintID: sid, boxIndex: k % 6, intervalSeconds: 300))
        }
    }
}

/// The app icon: a paper tile with a notebook row of three boxes.
struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(LinearGradient(colors: [Color(nsColor: NSColor(hex: 0xFDFBF6)), Color(nsColor: NSColor(hex: 0xF1ECE1))],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.18), radius: 28, y: 14)
            VStack(spacing: 0) {
                HStack(spacing: 46) {
                    BoxView(state: .worked, size: 190)
                    BoxView(state: .worked, size: 190)
                    BoxView(state: .pending, mode: .running, progress: 0.45, size: 190)
                }
                .padding(.bottom, 54)
                .background(alignment: .bottom) {
                    Rectangle().fill(Color(nsColor: NSColor(hex: 0xDCD5C7))).frame(width: 740, height: 6)
                }
            }
            .environment(\.colorScheme, .light)
        }
        .frame(width: 1024, height: 1024)
    }
}
