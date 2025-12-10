//
//  WeeklyPickChangeChartView.swift
//  PickAgent
//
//  Created by ChatGPT on 6/2/2025.
//

import SwiftUI
import Charts

struct WeeklyPickChangeChartView: View {
    @ObservedObject private var viewModel: ChartsViewModel
    let refreshTrigger: Bool

    init(viewModel: ChartsViewModel, refreshTrigger: Bool = false) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.refreshTrigger = refreshTrigger
    }

    private var orderedPoints: [WeeklyPickChangeSeries.Point] {
        viewModel.weeklyPickChanges.sorted { $0.weekStart < $1.weekStart }
    }

    private var xAxisValues: [Date] {
        let points = orderedPoints
        guard points.count > 1 else {
            return points.map(\.weekStart)
        }

        let stride = max(1, points.count / 6)
        return points.enumerated().compactMap { index, point in
            (index % stride == 0 || index == points.count - 1) ? point.weekStart : nil
        }
    }

    private var yDomain: ClosedRange<Double> {
        let magnitudes = orderedPoints.map { abs($0.percentageChange) }
        let maxMagnitude = magnitudes.max() ?? 0
        let padded = max(maxMagnitude + max(5, maxMagnitude * 0.2), 10)
        return -padded...padded
    }

    private var latestChangeText: String {
        guard let latest = orderedPoints.last else {
            return "No recent data"
        }

        let formatted = String(format: "%@%.1f%%", latest.percentageChange >= 0 ? "+" : "", latest.percentageChange)
        return "Latest week: \(formatted)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if viewModel.isLoadingWeeklyPickChanges && viewModel.weeklyPickChanges.isEmpty {
                    loadingView
                } else if let error = viewModel.weeklyPickChangesError {
                    errorView(message: error)
                } else if orderedPoints.isEmpty {
                    emptyStateView
                } else {
                    chartContent
                }
            }
        }
        .padding(.trailing)
        .padding(.leading, 8)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .task {
            await viewModel.loadWeeklyPickChanges()
        }
        .refreshable {
            await viewModel.refreshWeeklyPickChanges()
        }
        .onChange(of: refreshTrigger) { _, _ in
            Task {
                await viewModel.refreshWeeklyPickChanges()
            }
        }
    }

    private var chartContent: some View {
        VStack(alignment: .leading) {
            Text(latestChangeText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)

            Chart {
                RuleMark(y: .value("No change", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(.secondary)

                ForEach(orderedPoints) { point in
                    LineMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Change", point.percentageChange)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.teal)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineJoin: .round))

                    PointMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Change", point.percentageChange)
                    )
                    .foregroundStyle(.teal)
                    .symbolSize(18)
                }
            }
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text("\(Int(number.rounded()))%")
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisValues) { value in
                    if let date = value.as(Date.self) {
                        AxisGridLine()
                        AxisValueLabel(centered: false, anchor: .topTrailing) {
                            Text(Self.weekLabel(for: date))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
            Spacer()
        }
        .frame(height: 140)
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load weekly changes")
                .font(.subheadline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task {
                    await viewModel.refreshWeeklyPickChanges()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No picks recorded yet")
                .font(.subheadline)
            Text("Week-over-week changes will appear once picks are logged.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let isoCalendar = Calendar(identifier: .iso8601)

    private static func weekLabel(for date: Date) -> String {
        let weekNumber = isoCalendar.component(.weekOfYear, from: date)
        return "W\(weekNumber)"
    }
}
