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

    var body: some View {
        NavigationStack {
            List {
                Section("Items Packed") {
                    if dailyItemBreakdown.isEmpty {
                        ContentUnavailableView("No Packing Data",
                                               systemImage: "chart.bar",
                                               description: Text("Import runs to visualize daily packing totals."))
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ItemsPackedChart(data: dailyItemBreakdown)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Machines")
        }
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
