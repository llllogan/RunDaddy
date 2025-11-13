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
    @State private var selectedPeriod: SkuPeriod = .week

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 2) {
                Text("Data for the last ")
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
            }
            .font(.subheadline)
            .foregroundStyle(.primary)

            if currentPeriodData.isEmpty {
                Text("No data is available for the selected period.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart {
                    ForEach(currentPeriodData) { dayStat in
                        if let dayDate = chartDate(from: dayStat.date) {
                            LineMark(
                                x: .value("Day", dayDate),
                                y: .value("Total Items", dayStat.total)
                            )
                            .foregroundStyle(.gray)
                            .lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.catmullRom)
                            .symbol(Circle())
                        }

                        ForEach(dayStat.locations) { location in
                            if let dayDate = chartDate(from: dayStat.date) {
                                BarMark(
                                    x: .value("Date", dayDate),
                                    y: .value("Count", location.count)
                                )
                                .foregroundStyle(colorForLocation(location.name))
                                .position(by: .value("Location", location.name))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(formatLabel(for: date))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartYScale(domain: 0...maxYValue)
                .chartLegend(position: .bottom) {
                    HStack(spacing: 12) {
                        ForEach(uniqueLocations, id: \.self) { location in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(colorForLocation(location))
                                    .frame(width: 8, height: 8)
                                Text(location)
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 230)
            }
        }
        .padding()
    }

    private var currentPeriodData: [SkuDayStat] {
        let data: [SkuDayStat]
        switch selectedPeriod {
        case .week:
            data = stats.periods.week
        case .month:
            data = stats.periods.month
        case .quarter:
            data = stats.periods.quarter
        }

        return data.sorted { (chartDate(from: $0.date) ?? .distantPast) < (chartDate(from: $1.date) ?? .distantPast) }
    }

    private var uniqueLocations: [String] {
        var seen: [String] = []
        for day in currentPeriodData {
            for location in day.locations {
                if !seen.contains(location.name) {
                    seen.append(location.name)
                }
            }
        }
        return seen
    }

    private var maxYValue: Double {
        let maxLocation = currentPeriodData
            .flatMap { $0.locations.map { Double($0.count) } }
            .max() ?? 1
        let maxTotal = currentPeriodData
            .map { Double($0.total) }
            .max() ?? 1
        return max(max(maxLocation, maxTotal), 1) * 1.2
    }

    private func chartDate(from string: String) -> Date? {
        Self.inputDateFormatter.date(from: string)
    }

    private func formatLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func colorForLocation(_ location: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]
        let index = uniqueLocations.firstIndex(of: location) ?? 0
        return palette[index % palette.count]
    }

    private static let inputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

enum SkuPeriod: Int, CaseIterable, Identifiable {
    case week
    case month
    case quarter

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .quarter: return "Quarter"
        }
    }
}
