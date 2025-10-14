//
//  StatsView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    @Query private var runCoils: [RunCoil]

    init() {
        _runCoils = Query()
    }

    private var machineStats: [AggregateStat] {
        aggregateStats(
            keyPath: { $0.coil.machine.id },
            labelPath: { $0.coil.machine.name }
        )
    }

    private var itemStats: [AggregateStat] {
        aggregateStats(
            keyPath: { $0.coil.item.id },
            labelPath: { $0.coil.item.name }
        )
    }

    private var topMachines: [AggregateStat] {
        Array(machineStats.prefix(5))
    }

    private var topItems: [AggregateStat] {
        Array(itemStats.prefix(5))
    }

    private var totalMachinePick: Double {
        machineStats.reduce(0) { $0 + $1.total }
    }

    private var totalItemPick: Double {
        itemStats.reduce(0) { $0 + $1.total }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    StatsSection(title: "Top Machines",
                                 data: topMachines,
                                 chartData: machineStats,
                                 total: totalMachinePick,
                                 emptyMessage: "No machine restocks yet.")

                    StatsSection(title: "Top Items",
                                 data: topItems,
                                 chartData: itemStats,
                                 total: totalItemPick,
                                 emptyMessage: "No item restocks yet.")
                }
                .padding(.horizontal)
                .padding(.top, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stats")
        }
    }

    private func aggregateStats(keyPath: (RunCoil) -> String,
                                labelPath: (RunCoil) -> String) -> [AggregateStat] {
        let grouped = Dictionary(grouping: runCoils) { keyPath($0) }
        return grouped.compactMap { key, values in
            guard let first = values.first else { return nil }
            let total = values.reduce(into: 0) { $0 += $1.pick }
            return AggregateStat(id: key,
                                 label: labelPath(first),
                                 total: Double(total))
        }
        .sorted { lhs, rhs in
            if lhs.total == rhs.total {
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            return lhs.total > rhs.total
        }
    }
}

private struct StatsSection: View {
    let title: String
    let data: [AggregateStat]
    let chartData: [AggregateStat]
    let total: Double
    let emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            if chartData.isEmpty {
                ContentUnavailableView(emptyMessage,
                                       systemImage: "chart.pie",
                                       description: Text("Restock some runs to generate stats."))
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .background(Color(.secondarySystemBackground), ignoresSafeAreaEdges: [])
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                VStack(spacing: 16) {
                    DonutChart(data: chartData)
                        .frame(height: 220)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(data.enumerated()), id: \.element.id) { index, stat in
                            HStack {
                                Text("\(index + 1).")
                                    .font(.headline)
                                    .frame(width: 28, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(stat.label)
                                        .font(.headline)
                                    ProgressView(value: total == 0 ? 0 : stat.total / total)
                                        .tint(.accentColor)
                                    Text("Total stocked: \(Int(stat.total))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }
}

private struct DonutChart: View {
    let data: [AggregateStat]

    var body: some View {
        Chart(data) { entry in
            SectorMark(
                angle: .value("Restock", entry.total),
                innerRadius: .ratio(0.55)
            )
            .foregroundStyle(by: .value("Label", entry.label))
        }
        .chartLegend(.hidden)
    }
}

private struct AggregateStat: Identifiable {
    let id: String
    let label: String
    let total: Double
}

#Preview {
    StatsView()
        .modelContainer(PreviewFixtures.container)
}
