//
//  SkuStatsChartView.swift
//  PickAgent
//
//  Created by Logan Janssen on 11/13/2025.
//

import SwiftUI
import Charts

struct SkuStatsChartView: View {
    let refreshTrigger: Bool
    @ObservedObject private var viewModel: ChartsViewModel
    @State private var selectedRange: RangeOption
    
    enum RangeOption: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        case quarter = 90
        
        var id: Int { rawValue }
        
        var label: String {
            switch self {
            case .week: return "Week"
            case .month: return "Month"
            case .quarter: return "Quarter"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 2) {
                Text("Data for the last ")
                Menu {
                    ForEach(RangeOption.allCases) { range in
                        Button(action: {
                            selectedRange = range
                            viewModel.updateLookbackDays(range.rawValue)
                        }) {
                            HStack {
                                Text(range.label)
                                if selectedRange == range {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChip(label: selectedRange.label)
                }
                .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .foregroundStyle(.primary)
            // Chart
            Chart {
                ForEach(Array(currentPeriodData.enumerated()), id: \.offset) { index, dayStat in
                    ForEach(dayStat.locations) { location in
                        BarMark(
                            x: .value("Date", index),
                            y: .value("Count", location.count)
                        )
                        .foregroundStyle(colorForLocation(location.name))
                        .position(by: .value("Location", location.name))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let index = value.as(Int.self), index < currentPeriodData.count {
                            Text(formatChartDate(currentPeriodData[index].date))
                                .font(.caption)
                                .rotationEffect(.degrees(-45))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)")
                                .font(.caption)
                        }
                    }
                }
            }
            .chartLegend(position: .bottom) {
                HStack {
                    ForEach(uniqueLocations, id: \.self) { location in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(colorForLocation(location))
                                .frame(width: 8, height: 8)
                            Text(location)
                                .font(.caption)
                        }
                    }
                }
            }
            .frame(height: 200)
        }
        .padding()
    }
    
    private var currentPeriodData: [SkuDayStat] {
        switch selectedPeriod {
        case .week:
            return stats.periods.week
        case .month:
            return stats.periods.month
        case .quarter:
            return stats.periods.quarter
        }
    }
    
    private var uniqueLocations: [String] {
        Set(currentPeriodData.flatMap { $0.locations.map { $0.name } }).sorted()
    }
    
    private func formatChartDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func colorForLocation(_ location: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]
        let index = uniqueLocations.firstIndex(of: location) ?? 0
        return colors[index % colors.count]
    }
}

enum SkuPeriod: CaseIterable {
    case week
    case month
    case quarter
    
    var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .quarter: return "Quarter"
        }
    }
}
