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

    private var metricsItems: [BentoItem] {
        let comparison = itemsPackedComparisonMetric()
        let average = sevenDayAverageMetric()

        return [
            BentoItem(title: "Today vs Last Week",
                      value: comparison.value,
                      subtitle: comparison.subtitle,
                      symbolName: comparison.symbolName,
                      symbolTint: comparison.tint,
                      isProminent: true),
            BentoItem(title: "7-Day Average",
                      value: average.value,
                      subtitle: average.subtitle,
                      symbolName: average.symbolName,
                      symbolTint: average.tint,
                      isProminent: true)
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Items packed this week") {
                    if dailyItemBreakdown.isEmpty {
                        ContentUnavailableView("No Packing Data",
                                               systemImage: "chart.bar",
                                               description: Text("Import runs to visualize daily packing totals."))
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ItemsPackedChart(data: dailyItemBreakdown)
                    }
                }

                Section("Recent Insights") {
                    StaggeredBentoGrid(items: metricsItems, columnCount: 2)
                        .padding(.horizontal, 4)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Info")
        }
    }

    private func itemsPackedComparisonMetric() -> (value: String,
                                                   subtitle: String?,
                                                   symbolName: String,
                                                   tint: Color) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastWeekDate = calendar.date(byAdding: .day, value: -7, to: today)

        let todayTotal = totalItemsByDay[today]
        let lastWeekTotal = lastWeekDate.flatMap { totalItemsByDay[$0] }

        let subtitle: String? = {
            if todayTotal == nil && lastWeekTotal == nil {
                return nil
            }
            let todayString = todayTotal.map { formatItems($0) } ?? "—"
            let lastWeekString = lastWeekTotal.map { formatItems($0) } ?? "—"
            return "Today \(todayString) • Last Week \(lastWeekString)"
        }()

        guard let todayTotal else {
            return (value: "—",
                    subtitle: "No data for today",
                    symbolName: "questionmark.circle",
                    tint: .gray)
        }

        guard let lastWeekTotal else {
            return (value: "—",
                    subtitle: "No data from last week",
                    symbolName: "questionmark.circle",
                    tint: .gray)
        }

        guard lastWeekTotal != 0 else {
            if todayTotal == 0 {
                return (value: "0%",
                        subtitle: subtitle ?? "No items recorded",
                        symbolName: "equal.circle",
                        tint: .secondary)
            } else {
                return (value: "—",
                        subtitle: "Add more data for last week to compare",
                        symbolName: "exclamationmark.triangle",
                        tint: .orange)
            }
        }

        let percentChange = ((todayTotal - lastWeekTotal) / lastWeekTotal) * 100
        let formattedChange = formatPercent(percentChange)

        if percentChange > 0 {
            return (value: formattedChange,
                    subtitle: subtitle,
                    symbolName: "arrow.up.forward",
                    tint: .green)
        } else if percentChange < 0 {
            return (value: formattedChange,
                    subtitle: subtitle,
                    symbolName: "arrow.down.forward",
                    tint: .pink)
        } else {
            return (value: "0%",
                    subtitle: subtitle,
                    symbolName: "equal.circle",
                    tint: .secondary)
        }
    }

    private func sevenDayAverageMetric() -> (value: String,
                                             subtitle: String,
                                             symbolName: String,
                                             tint: Color) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let days = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }

        let totals = days.map { date in
            totalItemsByDay[date] ?? 0
        }

        let totalItems = totals.reduce(0, +)
        let average = totalItems / Double(days.count)

        if totalItems == 0 {
            return (value: "0 / day",
                    subtitle: "No packing activity in the last week",
                    symbolName: "calendar.badge.exclamationmark",
                    tint: .gray)
        }

        return (value: "\(formatItems(average, fractionDigits: 0...1)) / day",
                subtitle: "Total \(formatItems(totalItems)) items in 7 days",
                symbolName: "chart.bar.doc.horizontal",
                tint: .indigo)
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
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let dateValue = value.as(Date.self) {
                        Text(dateValue, format: .dateTime.month(.abbreviated).day())
                    }
                }
            }
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
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
