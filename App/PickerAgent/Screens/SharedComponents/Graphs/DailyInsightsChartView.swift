//
//  DailyInsightsChartView.swift
//  PickAgent
//
//  Created by Logan Janssen on 4/11/2025.
//

import SwiftUI
import Charts

struct DailyInsightsChartView: View {
    let session: AuthSession
    let refreshTrigger: Bool
    
    @StateObject private var viewModel: ChartsViewModel
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
    
    init(session: AuthSession, refreshTrigger: Bool = false) {
        self.session = session
        self.refreshTrigger = refreshTrigger
        _viewModel = StateObject(wrappedValue: ChartsViewModel(session: session))
        self._selectedRange = State(initialValue: .month)
    }

    private var lookbackText: String {
        let value = viewModel.dailyInsightsLookbackDays > 0 ? viewModel.dailyInsightsLookbackDays : viewModel.dailyInsights.count
        return value == 1 ? "1 day" : "\(value) days"
    }

    private var weekStartDates: [Date] {
        let calendar = Calendar.current
        let starts = viewModel.dailyInsights.compactMap { point in
            calendar.dateInterval(of: .weekOfYear, for: point.start)?.start
        }
        let uniqueStarts = Set(starts)
        return uniqueStarts.sorted()
    }

    private var maxYValue: Double {
        let maxTotal = viewModel.dailyInsights.map { Double($0.totalItems) }.max() ?? 1
        let maxPacked = viewModel.dailyInsights.map { Double($0.itemsPacked) }.max() ?? 1
        let maxPoint = max(maxTotal, maxPacked)
        return max(maxPoint * 1.15, 1)
    }
    
    private var isTrendingUp: Bool {
        guard viewModel.dailyInsights.count >= 2 else { return false }
        
        let sortedPoints = viewModel.dailyInsights.sorted { $0.start < $1.start }
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
                ForEach(viewModel.dailyInsights) { point in
                    
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
        .task {
            await viewModel.loadDailyInsights()
        }
        .refreshable {
            await viewModel.refreshInsights()
        }
        .onAppear {
            let closestRange = RangeOption.allCases.min(by: { abs($0.rawValue - viewModel.dailyInsightsLookbackDays) < abs($1.rawValue - viewModel.dailyInsightsLookbackDays) })
            if let range = closestRange {
                selectedRange = range
            }
        }
        .onChange(of: viewModel.dailyInsightsLookbackDays) { _, newDays in
            let closestRange = RangeOption.allCases.min(by: { abs($0.rawValue - newDays) < abs($1.rawValue - newDays) })
            if let range = closestRange {
                selectedRange = range
            }
        }
        .onChange(of: refreshTrigger) { _, _ in
            Task {
                await viewModel.refreshInsights()
            }
        }
    }
}
