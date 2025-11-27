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
                Chart(orderedPoints) { point in
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

                    LineMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Machines", point.totalMachines)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineJoin: .round))

                    PointMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Machines", point.totalMachines)
                    )
                    .foregroundStyle(.purple)
                }
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing)
                }
                .chartXAxis {
                    AxisMarks(values: orderedPoints.map { $0.weekStart }) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(Self.weekLabel(for: date))
                                    .font(.caption2.weight(.light))
                            }
                        }
                    }
                }
                .chartYScale(domain: minValue...maxValue)
                .frame(height: 170)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func weekLabel(for date: Date) -> String {
        let weekNumber = isoCalendar.component(.weekOfYear, from: date)
        return "W\(weekNumber)"
    }
}
