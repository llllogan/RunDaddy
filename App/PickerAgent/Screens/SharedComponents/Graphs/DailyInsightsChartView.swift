//
//  DailyInsightsChartView.swift
//  PickAgent
//
//  Created by Logan Janssen on 4/11/2025.
//

import SwiftUI
import Charts

struct DailyInsightsChartView: View {
    let points: [DailyInsights.Point]
    let lookbackDays: Int
    let onRangeChange: ((Int) -> Void)?
    
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
    
    init(points: [DailyInsights.Point], lookbackDays: Int, onRangeChange: ((Int) -> Void)? = nil) {
        self.points = points
        self.lookbackDays = lookbackDays
        self.onRangeChange = onRangeChange
        
        // Find the closest range option to the current lookbackDays
        let closestRange = RangeOption.allCases.min(by: { abs($0.rawValue - lookbackDays) < abs($1.rawValue - lookbackDays) })
        self._selectedRange = State(initialValue: closestRange ?? .month)
    }

    private var lookbackText: String {
        let value = lookbackDays > 0 ? lookbackDays : points.count
        return value == 1 ? "1 day" : "\(value) days"
    }

    private var weekStartDates: [Date] {
        let calendar = Calendar.current
        let starts = points.compactMap { point in
            calendar.dateInterval(of: .weekOfYear, for: point.start)?.start
        }
        let uniqueStarts = Set(starts)
        return uniqueStarts.sorted()
    }

    private var maxYValue: Double {
        let maxTotal = points.map { Double($0.totalItems) }.max() ?? 1
        let maxPacked = points.map { Double($0.itemsPacked) }.max() ?? 1
        let maxPoint = max(maxTotal, maxPacked)
        return max(maxPoint * 1.15, 1)
    }
    
    private var isTrendingUp: Bool {
        guard points.count >= 2 else { return false }
        
        let sortedPoints = points.sorted { $0.start < $1.start }
        guard let today = sortedPoints.last, let yesterday = sortedPoints.dropLast().last else { return false }
        
        return today.itemsPacked >= yesterday.itemsPacked
    }
    
    private var trendColor: Color {
        isTrendingUp ? Theme.trendUp : Theme.trendDown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    Text("Items packed over the last ")
                    Menu {
                        ForEach(RangeOption.allCases) { range in
                            Button(action: {
                                selectedRange = range
                                onRangeChange?(range.rawValue)
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
                        HStack(spacing: 2) {
                            Text(selectedRange.label)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(4)
                    .padding(.horizontal, 6)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
                
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 8, height: 8)
                        Text("Total Items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(trendColor)
                            .frame(width: 8, height: 8)
                        Text("Items Packed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Chart {
                // Items packed line with area mark
                ForEach(points) { point in
                    
                    AreaMark(
                        x: .value("Day", point.start, unit: .day),
                        y: .value("Items Packed", point.itemsPacked),
                        series: .value("packed", "A")
                    )
                    .foregroundStyle(trendColor.opacity(0.2))
                    .interpolationMethod(.stepCenter)
                    
                    LineMark(
                        x: .value("Day", point.start, unit: .day),
                        y: .value("Total Items", point.totalItems),
                        series: .value("total", "B")
                    )
                    .foregroundStyle(Color.gray)
                    .lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.stepCenter)
                    
                    LineMark(
                        x: .value("Day", point.start, unit: .day),
                        y: .value("Items Packed", point.itemsPacked),
                        series: .value("packed", "A")
                    )
                    .foregroundStyle(trendColor)
                    .lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.stepCenter)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(preset: .automatic) { value in
                    if let dateValue = value.as(Date.self) {
                        AxisGridLine()
                        AxisValueLabel {
                            Text(dateValue, format: Date.FormatStyle()
                                .month(.abbreviated)
                                .day())
                        }
                    }
                }
            }
            .chartYScale(domain: 0...maxYValue)
            .frame(maxHeight: 180)
        }
        .padding()
    }
}
