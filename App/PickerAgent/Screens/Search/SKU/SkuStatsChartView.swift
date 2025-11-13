//
//  SkuStatsChartView.swift
//  PickerAgent
//
//  Created by Logan Janssen on 11/13/2025.
//

import SwiftUI
import Charts

struct SkuStatsChartView: View {
    let stats: SkuStatsResponse
    @Binding var selectedPeriod: SkuPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 2) {
                Text("Totals for the last ")
                Menu {
                    ForEach(SkuPeriod.allCases) { period in
                        Button(action: { selectedPeriod = period }) {
                            HStack {
                                Text(period.displayName)
                                if selectedPeriod == period {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChip(label: selectedPeriod.displayName)
                }
                .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.subheadline)
            .foregroundStyle(.primary)

            if hasChartData {
                Chart {
                    ForEach(stats.points, id: \.date) { point in
                        ForEach(point.machines) { machine in
                            if let dayDate = chartDate(from: point.date) {
                                let dayLabel = formatLabel(for: dayDate)
                                let machineLabel = machine.machineName ?? machine.machineCode
                                BarMark(
                                    x: .value("Day", dayLabel),
                                    y: .value("Items", machine.count)
                                )
                                .foregroundStyle(by: .value("Machine", machineLabel))
                            }
                        }
                    }
                }
                .chartLegend(position: .top, alignment: .leading)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: orderedDayLabels) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...maxYValue)
                .frame(height: 240)
            } else {
                Text("No data is available for the selected period.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
    }

    private var hasChartData: Bool {
        stats.points.contains { $0.totalItems > 0 }
    }

    private var maxYValue: Double {
        let maxPoint = stats.points.map { Double($0.totalItems) }.max() ?? 1
        return max(maxPoint, 1) * 1.2
    }

    private func chartDate(from string: String) -> Date? {
        Self.inputDateFormatter.date(from: string)
    }

    private func formatLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private var orderedDayLabels: [String] {
        stats.points
            .compactMap { chartDate(from: $0.date).map(formatLabel(for:)) }
            .reducingUnique()
    }

    private static let inputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

private extension Sequence where Element: Hashable {
    func reducingUnique() -> [Element] {
        var seen = Set<Element>()
        return compactMap { element in
            let inserted = seen.insert(element).inserted
            return inserted ? element : nil
        }
    }
}
