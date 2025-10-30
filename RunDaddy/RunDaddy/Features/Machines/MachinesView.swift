//
//  MachinesView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Charts
import SwiftData
import SwiftUI

struct MachinesView: View {
    @Query private var runCoils: [RunCoil]
    @State private var selectedRange: ChartRange = .week

    init() {
        _runCoils = Query()
    }

    private var dailyItemBreakdown: [DailyItemBreakdown] {
        let calendar = Calendar.current
        let grouped = runCoils.reduce(into: [DailyItemKey: Double]()) { result, runCoil in
            let day = calendar.startOfDay(for: runCoil.run.date)
            let itemName = runCoil.coil.item.name
            let key = DailyItemKey(date: day, itemName: itemName)
            result[key, default: 0] += Double(runCoil.pick)
        }

        return grouped
            .map { entry in
                DailyItemBreakdown(date: entry.key.date,
                                   itemName: entry.key.itemName,
                                   total: entry.value)
            }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.itemName.localizedCaseInsensitiveCompare(rhs.itemName) == .orderedAscending
                }
                return lhs.date < rhs.date
            }
    }

    private var totalItemsByDay: [Date: Double] {
        let calendar = Calendar.current
        return runCoils.reduce(into: [Date: Double]()) { result, runCoil in
            let day = calendar.startOfDay(for: runCoil.run.date)
            result[day, default: 0] += Double(runCoil.pick)
        }
    }

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let chartRange = selectedRange.chartDateRange(relativeTo: today, calendar: calendar)
        let metricsRange = selectedRange.metricsDateRange(relativeTo: today, calendar: calendar)
        let filteredBreakdown = dailyItemBreakdown.filter { chartRange.contains($0.date) }
        let metrics = metricsItems(for: selectedRange,
                                   chartRange: chartRange,
                                   metricsRange: metricsRange,
                                   today: today,
                                   calendar: calendar)

        return NavigationStack {
            List {
                Section("Items Packed") {
                    if dailyItemBreakdown.isEmpty {
                        ContentUnavailableView("No Packing Data",
                                               systemImage: "chart.bar",
                                               description: Text("Import runs to visualize daily packing totals."))
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ItemsPackedChart(data: filteredBreakdown, dateRange: chartRange)
                                .overlay {
                                    if filteredBreakdown.isEmpty {
                                        ContentUnavailableView("No Data in Range",
                                                               systemImage: "calendar.badge.exclamationmark",
                                                               description: Text("Try a different period to compare packing activity."))
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(Color.clear)
                                            .allowsHitTesting(false)
                                    }
                                }

                            Picker("", selection: $selectedRange) {
                                ForEach(ChartRange.allCases) { range in
                                    Text(range.label(for: today, calendar: calendar)).tag(range)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Recent Insights") {
                    StaggeredBentoGrid(items: metrics, columnCount: 2)
                        .padding(.horizontal, 4)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Info")
        }
    }

    private func metricsItems(for selection: ChartRange,
                              chartRange: ClosedRange<Date>,
                              metricsRange: ClosedRange<Date>,
                              today: Date,
                              calendar: Calendar) -> [BentoItem] {
        [
            comparisonMetric(for: selection,
                             chartRange: chartRange,
                             metricsRange: metricsRange,
                             today: today,
                             calendar: calendar),
            averageMetric(for: selection,
                          chartRange: chartRange,
                          calendar: calendar)
        ]
    }

    private func comparisonMetric(for selection: ChartRange,
                                  chartRange: ClosedRange<Date>,
                                  metricsRange: ClosedRange<Date>,
                                  today: Date,
                                  calendar: Calendar) -> BentoItem {
        let subtitle = selection.comparisonSubtitle(today: today, calendar: calendar)
        let result: PercentChangeResult
        let title = selection.comparisonTitle

        switch selection {
        case .week:
            let current = totalItems(in: metricsRange)
            let previousRange = offsetRange(metricsRange, byDays: -7, calendar: calendar)
            let previous = totalItems(in: previousRange)
            result = percentChangeResult(current: current, previous: previous)

        case .fortnight:
            let current = totalItemsByDay[today]
            let comparisonDate = calendar.date(byAdding: .day, value: -7, to: today).map { calendar.startOfDay(for: $0) }
            let previous = comparisonDate.flatMap { totalItemsByDay[$0] }
            result = percentChangeResult(current: current, previous: previous)

        case .month:
            let currentMonthStart = calendar.startOfMonth(containing: today)
            let currentRange = currentMonthStart...today
            let previousPeriodEnd = calendar.date(byAdding: .month, value: -1, to: today).map { calendar.startOfDay(for: $0) } ?? today
            let previousMonthStart = calendar.startOfMonth(containing: previousPeriodEnd)
            let previousRange = previousMonthStart...previousPeriodEnd

            let current = totalItems(in: currentRange)
            let previous = totalItems(in: previousRange)
            result = percentChangeResult(current: current, previous: previous)
        }

        return BentoItem(title: title,
                         value: result.value,
                         subtitle: subtitle,
                         symbolName: result.symbolName,
                         symbolTint: result.tint,
                         isProminent: true)
    }

    private func averageMetric(for selection: ChartRange,
                               chartRange: ClosedRange<Date>,
                               calendar: Calendar) -> BentoItem {
        let dayTotals = totalsPerDay(in: chartRange, calendar: calendar)
        let totalItems = dayTotals.reduce(0, +)
        let dayCount = dayTotals.count
        let subtitle = selection.averageSubtitle

        if dayCount == 0 || totalItems == 0 {
            return BentoItem(title: selection.averageTitle,
                              value: "0 / day",
                              subtitle: subtitle,
                              symbolName: "calendar.badge.exclamationmark",
                              symbolTint: .gray,
                              isProminent: true)
        }

        let average = totalItems / Double(dayCount)
        return BentoItem(title: selection.averageTitle,
                          value: "\(formatItems(average, fractionDigits: 0...1)) / day",
                          subtitle: subtitle,
                          symbolName: "chart.bar.doc.horizontal",
                          symbolTint: .indigo,
                          isProminent: true)
    }

    private func totalItems(in range: ClosedRange<Date>) -> Double? {
        let matching = totalItemsByDay.filter { range.contains($0.key) }
        guard !matching.isEmpty else { return nil }
        return matching.values.reduce(0, +)
    }

    private func totalsPerDay(in range: ClosedRange<Date>, calendar: Calendar) -> [Double] {
        guard range.lowerBound <= range.upperBound else { return [] }
        var values: [Double] = []
        var cursor = range.lowerBound
        while cursor <= range.upperBound {
            values.append(totalItemsByDay[cursor] ?? 0)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return values
    }

    private func offsetRange(_ range: ClosedRange<Date>, byDays days: Int, calendar: Calendar) -> ClosedRange<Date> {
        guard let lower = calendar.date(byAdding: .day, value: days, to: range.lowerBound),
              let upper = calendar.date(byAdding: .day, value: days, to: range.upperBound) else {
            return range
        }
        return lower...upper
    }

    private func percentChangeResult(current: Double?, previous: Double?) -> PercentChangeResult {
        guard let current else {
            return PercentChangeResult(value: "—",
                                       symbolName: "questionmark.circle",
                                       tint: .gray)
        }

        guard let previous else {
            return PercentChangeResult(value: "—",
                                       symbolName: "questionmark.circle",
                                       tint: .gray)
        }

        guard previous != 0 else {
            if current == 0 {
                return PercentChangeResult(value: "0%",
                                           symbolName: "equal.circle",
                                           tint: .secondary)
            } else {
                return PercentChangeResult(value: "—",
                                           symbolName: "exclamationmark.triangle",
                                           tint: .orange)
            }
        }

        let percentChange = ((current - previous) / previous) * 100
        let formattedChange = formatPercent(percentChange)

        if percentChange > 0 {
            return PercentChangeResult(value: formattedChange,
                                       symbolName: "arrow.up.forward",
                                       tint: .green)
        } else if percentChange < 0 {
            return PercentChangeResult(value: formattedChange,
                                       symbolName: "arrow.down.forward",
                                       tint: .pink)
        } else {
            return PercentChangeResult(value: "0%",
                                       symbolName: "equal.circle",
                                       tint: .secondary)
        }
    }

    private struct PercentChangeResult {
        let value: String
        let symbolName: String
        let tint: Color
    }

    private func formatItems(_ value: Double, fractionDigits: ClosedRange<Int> = 0...0) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    private func formatPercent(_ value: Double) -> String {
        let absolute = abs(value)
        let decimals = absolute < 10 ? 1 : 0
        let scaled = decimals == 0 ? value.rounded() : (value * 10).rounded() / 10
        return String(format: "%+.\(decimals)f%%", scaled)
    }
}

private struct ItemsPackedChart: View {
    let data: [DailyItemBreakdown]
    let dateRange: ClosedRange<Date>

    private var calendar: Calendar { Calendar.current }

    private var paddedDomain: ClosedRange<Date> {
        let lower = calendar.date(byAdding: .hour, value: -12, to: dateRange.lowerBound) ?? dateRange.lowerBound
        let endOfRange = calendar.date(byAdding: .day, value: 1, to: dateRange.upperBound) ?? dateRange.upperBound
        let upper = endOfRange
        return lower...upper
    }

    private var axisDates: [Date] {
        guard dateRange.lowerBound <= dateRange.upperBound else { return [] }
        var values: [Date] = []
        var cursor = dateRange.lowerBound
        while cursor <= dateRange.upperBound {
            values.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return values
    }

    var body: some View {
        Chart(data) { entry in
            BarMark(
                x: .value("Date", entry.date, unit: .day),
                y: .value("Items Packed", entry.total),
                width: .fixed(18)
            )
            .foregroundStyle(by: .value("Item", entry.itemName))
        }
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartYAxisLabel("Items Packed")
        .chartXScale(domain: paddedDomain)
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                if let dateValue = value.as(Date.self) {
                    AxisGridLine()
                    AxisValueLabel {
                        axisLabel(for: dateValue)
                    }
                }
            }
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func axisLabel(for date: Date) -> some View {
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 2 {
            Text(date, format: .dateTime.day())
        } else {
            let symbol = calendar.shortWeekdaySymbols[weekday - 1]
            Text(String(symbol.prefix(1)))
        }
    }
}

private enum ChartRange: String, CaseIterable, Identifiable {
    case week
    case fortnight
    case month

    var id: ChartRange { self }

    func label(for today: Date, calendar: Calendar) -> String {
        switch self {
        case .week:
            return "Week"
        case .fortnight:
            return "Fortnight"
        case .month:
            let monthSymbols = calendar.monthSymbols
            let index = calendar.component(.month, from: today) - 1
            if monthSymbols.indices.contains(index) {
                return monthSymbols[index]
            }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.dateFormat = "MMMM"
            return formatter.string(from: today)
        }
    }

    var comparisonTitle: String {
        switch self {
        case .week:
            return "Week vs Last Week"
        case .fortnight:
            return "Today vs Last Week"
        case .month:
            return "Month Over Month"
        }
    }

    var averageTitle: String {
        switch self {
        case .week:
            return "Week Average"
        case .fortnight:
            return "7-Day Average"
        case .month:
            return "30-Day Average"
        }
    }

    var averageSubtitle: String? {
        switch self {
        case .week:
            return "Week-to-date average"
        case .fortnight:
            return "Rolling 7 days"
        case .month:
            return "Last 30 days"
        }
    }

    func chartDateRange(relativeTo today: Date, calendar: Calendar) -> ClosedRange<Date> {
        switch self {
        case .week:
            let start = calendar.startOfWeek(containing: today)
            let end = calendar.endOfWeek(containing: today)
            return start...end

        case .fortnight:
            let end = today
            let start = calendar.date(byAdding: .day, value: -13, to: end).map { calendar.startOfDay(for: $0) } ?? end
            return start...end

        case .month:
            let end = today
            let start = calendar.date(byAdding: .day, value: -30, to: end).map { calendar.startOfDay(for: $0) } ?? end
            return start...end
        }
    }

    func metricsDateRange(relativeTo today: Date, calendar: Calendar) -> ClosedRange<Date> {
        switch self {
        case .week:
            let start = calendar.startOfWeek(containing: today)
            return start...today

        case .fortnight:
            let end = today
            let start = calendar.date(byAdding: .day, value: -6, to: end).map { calendar.startOfDay(for: $0) } ?? end
            return start...end

        case .month:
            let end = today
            let start = calendar.date(byAdding: .day, value: -30, to: end).map { calendar.startOfDay(for: $0) } ?? end
            return start...end
        }
    }

    func comparisonSubtitle(today: Date, calendar: Calendar) -> String {
        switch self {
        case .week:
            return "Week So Far"

        case .fortnight:
            let comparisonDate = calendar.date(byAdding: .day, value: -7, to: today) ?? today
            let weekdaySymbols = calendar.weekdaySymbols
            let rawIndex = calendar.component(.weekday, from: comparisonDate) - 1
            let boundedIndex = min(max(rawIndex, 0), weekdaySymbols.count - 1)
            let weekdayName = weekdaySymbols[boundedIndex]
            return "Today vs Last \(weekdayName)"

        case .month:
            let monthSymbols = calendar.monthSymbols
            let currentMonthIndex = calendar.component(.month, from: today) - 1
            let boundedCurrent = min(max(currentMonthIndex, 0), monthSymbols.count - 1)
            let currentMonth = monthSymbols[boundedCurrent]
            let previousDate = calendar.date(byAdding: .month, value: -1, to: today) ?? today
            let previousIndex = calendar.component(.month, from: previousDate) - 1
            let boundedPrevious = min(max(previousIndex, 0), monthSymbols.count - 1)
            let previousMonth = monthSymbols[boundedPrevious]
            return "\(currentMonth) vs \(previousMonth)"
        }
    }
}

private extension Calendar {
    func startOfMonth(containing date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        let start = self.date(from: components) ?? date
        return startOfDay(for: start)
    }

    func startOfWeek(containing date: Date) -> Date {
        let day = startOfDay(for: date)
        let weekday = component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        return self.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }

    func endOfWeek(containing date: Date) -> Date {
        let start = startOfWeek(containing: date)
        return self.date(byAdding: .day, value: 6, to: start) ?? start
    }
}

private struct DailyItemBreakdown: Identifiable, Hashable {
    let id: String
    let date: Date
    let itemName: String
    let total: Double

    init(date: Date, itemName: String, total: Double) {
        self.date = date
        self.itemName = itemName
        self.total = total
        self.id = "\(date.timeIntervalSinceReferenceDate)-\(itemName)"
    }
}

private struct DailyItemKey: Hashable {
    let date: Date
    let itemName: String
}

#Preview {
    NavigationStack {
        MachinesView()
            .navigationBarTitleDisplayMode(.inline)
    }
    .modelContainer(PreviewFixtures.container)
}
