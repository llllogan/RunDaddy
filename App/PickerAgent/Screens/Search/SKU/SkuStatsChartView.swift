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
                                let machineLabel = machine.machineName ?? machine.machineCode
                                BarMark(
                                    x: .value("Day", dayDate),
                                    y: .value("Items", machine.count)
                                )
                                .foregroundStyle(by: .value("Machine", machineLabel))
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: stats.points.compactMap { chartDate(from: $0.date) }) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(formatLabel(for: date))
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

    private static let inputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
