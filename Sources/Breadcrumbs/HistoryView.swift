import BreadcrumbsCore
import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: AppModel

    static let size = CGSize(width: 440, height: 430)

    var body: some View {
        let week = model.week
        let weekWorked = week.map(\.worked).reduce(0, +)
        let weekTotal = week.map(\.total).reduce(0, +)

        VStack(alignment: .leading, spacing: 22) {
            Text("History").font(Theme.serif(22, .semibold)).foregroundStyle(Theme.ink)
                .padding(.top, 14)

            HStack(alignment: .top, spacing: 14) {
                stat(value: "\(model.todayWorked)", label: "ticked today",
                     detail: model.todayMissed > 0 ? "\(model.todayMissed) missed" : "none missed")
                stat(value: "\(weekWorked)", label: "this week",
                     detail: weekTotal > 0 ? "\(Int((Double(weekWorked) / Double(weekTotal) * 100).rounded()))% ticked" : "no boxes yet")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Last 7 days").font(Theme.ui(12, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    legend(Theme.tick, "Ticked")
                    legend(Theme.missed, "Missed")
                }
                WeekBars(days: week, height: 120, barWidth: 26, showCounts: true, labelFont: Theme.ui(11, .medium))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Theme.paper)
    }

    private func stat(value: String, label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.number(40)).foregroundStyle(Theme.ink)
            Text(label).font(Theme.ui(12, .medium)).foregroundStyle(Theme.ink)
            Text(detail).font(Theme.ui(11)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.wash))
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(color).frame(width: 9, height: 9)
            Text(text).font(Theme.ui(10, .medium)).foregroundStyle(Theme.inkSoft)
        }
    }
}
