//
//  MachineDistributionChartView.swift
//  PickAgent
//
//  Created by ChatGPT on 5/30/2025.
//

import SwiftUI
import Charts

struct MachineDistributionChartView: View {
    @ObservedObject private var viewModel: ChartsViewModel
    let refreshTrigger: Bool

    init(viewModel: ChartsViewModel, refreshTrigger: Bool = false) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.refreshTrigger = refreshTrigger
    }

    private var orderedSlices: [DashboardMomentumSnapshot.MachineSlice] {
        viewModel.machinePickTotals.sorted { $0.totalPicks > $1.totalPicks }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Group {
                if viewModel.isLoadingMachinePickTotals && viewModel.machinePickTotals.isEmpty {
                    loadingView
                } else if let error = viewModel.machinePickTotalsError {
                    errorView(message: error)
                } else if viewModel.machinePickTotals.isEmpty {
                    emptyStateView
                } else {
                    chartAndLegend
                }
            }
        }
        .padding()
        .task {
            await viewModel.loadMachinePickTotals()
        }
        .refreshable {
            await viewModel.refreshMachinePickTotals()
        }
        .onChange(of: refreshTrigger) { _, _ in
            Task {
                await viewModel.refreshMachinePickTotals()
            }
        }
    }

    private var chartAndLegend: some View {
        Chart(orderedSlices) { slice in
            SectorMark(
                angle: .value("Pick Entries", slice.totalPicks)
            )
            .foregroundStyle(by: .value("Machine", slice.displayName))
        }
        .chartLegend(position: .trailing, alignment: .center)
        .frame(height: 240)
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
            Text("Couldn't load machines")
                .font(.subheadline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task {
                    await viewModel.refreshMachinePickTotals()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No picks recorded in the last 14 days")
                .font(.subheadline)
            Text("Machine activity will appear once pick entries are logged.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

struct MachineTouchesChartView: View {
    @ObservedObject private var viewModel: ChartsViewModel
    let refreshTrigger: Bool

    init(viewModel: ChartsViewModel, refreshTrigger: Bool = false) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.refreshTrigger = refreshTrigger
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Group {
                if viewModel.isLoadingMachineTouches && viewModel.machineTouches.isEmpty {
                    loadingView
                } else if let error = viewModel.machineTouchesError {
                    errorView(message: error)
                } else if viewModel.machineTouches.isEmpty {
                    emptyStateView
                } else {
                    MachineTouchesLineChart(points: viewModel.machineTouches)
                }
            }
        }
        .padding()
        .task {
            await viewModel.loadMachinePickTotals()
        }
        .refreshable {
            await viewModel.refreshMachinePickTotals()
        }
        .onChange(of: refreshTrigger) { _, _ in
            Task {
                await viewModel.refreshMachinePickTotals()
            }
        }
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
            Text("Couldn't load machine trends")
                .font(.subheadline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task {
                    await viewModel.refreshMachinePickTotals()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No machine activity yet")
                .font(.subheadline)
            Text("Machine counts appear once weekly pick entries land.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MachineTouchesLineChart: View {
    let points: [DashboardMomentumSnapshot.MachineTouchPoint]

    private var orderedPoints: [DashboardMomentumSnapshot.MachineTouchPoint] {
        points.sorted { $0.weekStart < $1.weekStart }
    }

    private var completedTrendPoints: [DashboardMomentumSnapshot.MachineTouchPoint] {
        Array(orderedPoints.dropLast())
    }

    private var trailingSegmentPoints: [DashboardMomentumSnapshot.MachineTouchPoint] {
        Array(orderedPoints.suffix(3))
    }

    private var maxValue: Double {
        let maxTotal = orderedPoints.map(\.totalMachines).max() ?? 0
        return max(Double(maxTotal), 1)
    }
    
    private var minValue: Double {
        let minTotal = orderedPoints.map(\.totalMachines).min() ?? 0
        return min(Double(minTotal), 1)
    }

    private static let isoCalendar = Calendar(identifier: .iso8601)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if orderedPoints.isEmpty {
                Text("Machine activity will appear once picks start landing each week.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Chart {
                    ForEach(orderedPoints) { point in
                        AreaMark(
                            x: .value("Week", point.weekStart),
                            y: .value("Machines", point.totalMachines)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    .purple.opacity(0.24),
                                    .purple.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        PointMark(
                            x: .value("Week", point.weekStart),
                            y: .value("Machines", point.totalMachines)
                        )
                        .foregroundStyle(.purple)
                        .symbolSize(18)
                    }

                    ForEach(completedTrendPoints) { point in
                        LineMark(
                            x: .value("Week", point.weekStart),
                            y: .value("Machines", point.totalMachines),
                            series: .value("Series", "Completed")
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(.purple)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineJoin: .round))
                    }

                }
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing)
                }
                .chartXAxis {
                    AxisMarks(values: orderedPoints.map { $0.weekStart }) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel(centered: false, anchor: .topTrailing) {
                                Text(Self.weekLabel(for: date))
                                    .font(.caption2.weight(.light))
                            }
                        }
                    }
                }
                .chartYScale(domain: minValue...maxValue)
                .frame(height: 170)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        ZStack {
                            if trailingSegmentPoints.count >= 2,
                               let previous = trailingSegmentPoints.dropLast().first,
                               let current = trailingSegmentPoints.dropLast().last,
                               let latest = trailingSegmentPoints.last,
                               let previousX = proxy.position(forX: previous.weekStart),
                               let previousY = proxy.position(forY: previous.totalMachines),
                               let currentX = proxy.position(forX: current.weekStart),
                               let currentY = proxy.position(forY: current.totalMachines),
                               let latestX = proxy.position(forX: latest.weekStart),
                               let latestY = proxy.position(forY: latest.totalMachines) {

                                let plotFrame = geometry[proxy.plotAreaFrame]

                                let adjustedPrevious = CGPoint(
                                    x: previousX + plotFrame.minX,
                                    y: previousY + plotFrame.minY
                                )
                                let adjustedCurrent = CGPoint(
                                    x: currentX + plotFrame.minX,
                                    y: currentY + plotFrame.minY
                                )
                                let adjustedLatest = CGPoint(
                                    x: latestX + plotFrame.minX,
                                    y: latestY + plotFrame.minY
                                )

                                let control1 = CGPoint(
                                    x: adjustedCurrent.x + (adjustedCurrent.x - adjustedPrevious.x) / 3,
                                    y: adjustedCurrent.y + (adjustedCurrent.y - adjustedPrevious.y) / 3
                                )
                                let control2 = CGPoint(
                                    x: adjustedLatest.x - (adjustedLatest.x - adjustedCurrent.x) / 3,
                                    y: adjustedLatest.y - (adjustedLatest.y - adjustedCurrent.y) / 3
                                )

                                Path { path in
                                    path.move(to: adjustedCurrent)
                                    path.addCurve(to: adjustedLatest, control1: control1, control2: control2)
                                }
                                .stroke(
                                    .purple,
                                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round, dash: [6, 4])
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func weekLabel(for date: Date) -> String {
        let weekNumber = isoCalendar.component(.weekOfYear, from: date)
        return "W\(weekNumber)"
    }
}
