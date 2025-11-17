//
//  PeriodComparisonChartView.swift
//  PickAgent
//
//  Created by ChatGPT on 5/30/2025.
//

import SwiftUI
import Charts

struct PeriodComparisonChartView: View {
    @ObservedObject private var viewModel: ChartsViewModel
    let refreshTrigger: Bool

    private struct ChartEntry: Identifiable {
        let id = UUID()
        let period: PackPeriodComparisons.PeriodKind
        let label: String
        let order: Int
        let value: Int
        let isCurrent: Bool

        var groupLabel: String {
            period.displayName
        }

        var legendLabel: String {
            label
        }
    }

    init(viewModel: ChartsViewModel, refreshTrigger: Bool = false) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.refreshTrigger = refreshTrigger
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Group {
                if viewModel.isLoadingPeriodComparisons && viewModel.packPeriodComparisons.isEmpty {
                    loadingView
                } else if let error = viewModel.packPeriodComparisonsError {
                    errorView(message: error)
                } else if chartEntries.isEmpty {
                    emptyStateView
                } else {
                    chart
                    progressSummary
                }
            }
        }
        .padding()
        .task {
            await viewModel.loadPeriodComparisons()
        }
        .refreshable {
            await viewModel.refreshPeriodComparisons()
        }
        .onChange(of: refreshTrigger) { _, _ in
            Task {
                await viewModel.refreshPeriodComparisons()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Current pace vs last three periods")
                .font(.subheadline)
                .foregroundStyle(.primary)
            Text("Bars compare packed items for the elapsed share of each week, month, or quarter.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                legendSwatch(color: Theme.trendUp, label: "Current period")
                legendSwatch(color: Color.gray.opacity(0.35), label: "Previous periods")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Chart {
                ForEach(chartEntries) { entry in
                    BarMark(
                        x: .value("Period", entry.groupLabel),
                        y: .value("Items", entry.value)
                    )
                    .position(by: .value("Slice", entry.order))
                    .foregroundStyle(color(for: entry))
                    .annotation(position: .top, alignment: .center) {
                        if entry.value > 0 {
                            Text(entry.value.formatted())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    if let label = value.as(String.self) {
                        AxisValueLabel {
                            Text(label)
                                .font(.caption)
                        }
                    }
                }
            }
            .frame(height: 240)
        }
    }

    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.packPeriodComparisons) { comparison in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(comparison.period.displayName) pace")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(comparison.progressPercentage, format: .number.precision(.fractionLength(0)))% complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let delta = comparison.averages.deltaPercentage {
                        let isUp = delta >= 0
                        HStack(spacing: 4) {
                            Image(systemName: isUp ? "arrow.up" : "arrow.down")
                            Text("\(abs(delta), format: .number.precision(.fractionLength(1)))% vs avg of last 3 \(comparison.period.displayName.lowercased())s")
                        }
                        .font(.caption2)
                        .foregroundStyle(isUp ? Theme.trendUp : Theme.trendDown)
                    } else {
                        Text("No historical data yet.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                if comparison.period != viewModel.packPeriodComparisons.last?.period {
                    Divider()
                }
            }
        }
    }

    private var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(height: 120)
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load period comparisons")
                .font(.subheadline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task {
                    await viewModel.refreshPeriodComparisons()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No packed items to compare yet")
                .font(.subheadline)
            Text("Once items are packed this chart will highlight how the current period stacks up.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendSwatch(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
        }
    }

    private func color(for entry: ChartEntry) -> Color {
        entry.isCurrent ? Theme.trendUp : Color.gray.opacity(0.35)
    }

    private var chartEntries: [ChartEntry] {
        viewModel.packPeriodComparisons.flatMap { comparison in
            var entries: [ChartEntry] = [
                ChartEntry(
                    period: comparison.period,
                    label: "Current",
                    order: 0,
                    value: comparison.currentPeriod.totalItems,
                    isCurrent: true
                ),
            ]

            let sortedHistorical = comparison.previousPeriods.sorted { $0.index < $1.index }

            for period in sortedHistorical {
                entries.append(
                    ChartEntry(
                        period: comparison.period,
                        label: "Prev \(period.index)",
                        order: period.index,
                        value: period.totalItems,
                        isCurrent: false
                    )
                )
            }

            return entries
        }
    }
}
