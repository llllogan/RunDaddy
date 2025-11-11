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
        let maxPoint = points.map { Double($0.totalItems) }.max() ?? 1
        return max(maxPoint * 1.15, 1)
    }
    
    private var isTrendingUp: Bool {
        guard points.count >= 2 else { return false }
        
        let sortedPoints = points.sorted { $0.start < $1.start }
        guard let today = sortedPoints.last, let yesterday = sortedPoints.dropLast().last else { return false }
        
        return today.totalItems > yesterday.totalItems
    }
    
    private var trendColor: Color {
        isTrendingUp ? Theme.trendUp : Theme.trendDown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Items picked over the last \(lookbackText)")
                .font(.subheadline)

            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Day", point.start, unit: .day),
                        y: .value("Items", point.totalItems)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [trendColor.opacity(0.35), .clear]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Day", point.start, unit: .day),
                        y: .value("Items", point.totalItems)
                    )
                    .foregroundStyle(trendColor)
                    .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: weekStartDates) { value in
                    if let dateValue = value.as(Date.self) {
                        AxisValueLabel {
                            Text(dateValue, format: Date.FormatStyle()
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