//
//  SkuBreakdownChartView.swift
//  PickAgent
//
//  Created by ChatGPT on 6/6/2025.
//

import SwiftUI
import Charts

struct SkuBreakdownChartView: View {
    let refreshTrigger: Bool
    @ObservedObject private var viewModel: ChartsViewModel
    @State private var selectedAggregation: PickEntryBreakdown.Aggregation

    init(viewModel: ChartsViewModel, refreshTrigger: Bool = false) {
        self.refreshTrigger = refreshTrigger
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _selectedAggregation = State(initialValue: viewModel.skuBreakdownAggregation)
    }

    private var orderedPoints: [PickEntryBreakdown.Point] {
        viewModel.skuBreakdownPoints.sorted { $0.start < $1.start }
    }

    private var lookbackDays: Int {
        let candidate = viewModel.skuBreakdownPeriods * selectedAggregation.baseDays
        if candidate > 0 {
            return candidate
        }
        return max(orderedPoints.count, selectedAggregation.baseDays)
    }

    private var lookbackText: String {
        let value = lookbackDays
        return value == 1 ? "1 day" : "\(value) days"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Pick entries per ")
                    Menu {
                        ForEach(PickEntryBreakdown.Aggregation.allCases) { aggregation in
                            Button {
                                selectedAggregation = aggregation
                                viewModel.updateSkuBreakdownAggregation(aggregation)
                            } label: {
                                HStack {
                                    Text(aggregation.displayName)
                                    if aggregation == selectedAggregation {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        filterChip(label: selectedAggregation.displayName)
                    }
                    .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .foregroundStyle(.primary)

                Text("Showing last \(lookbackText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.isLoadingSkuBreakdown && orderedPoints.isEmpty {
                ProgressView("Loading")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = viewModel.skuBreakdownError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if orderedPoints.isEmpty {
                Text("SKU activity will appear once picks start landing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                PickEntryBarChart(
                    points: orderedPoints,
                    showLegend: true,
                    maxHeight: 220
                )
            }
        }
        .padding()
        .task {
            await viewModel.loadSkuBreakdown(
                aggregation: viewModel.skuBreakdownAggregation,
                periods: viewModel.skuBreakdownPeriods
            )
        }
        .onChange(of: viewModel.skuBreakdownAggregation, initial: false) { _, newValue in
            selectedAggregation = newValue
        }
        .onChange(of: refreshTrigger) { _, _ in
            Task {
                await viewModel.refreshSkuBreakdown()
            }
        }
    }
}

struct PickEntryBarChart: View {
    let points: [PickEntryBreakdown.Point]
    var showLegend: Bool = true
    var maxHeight: CGFloat = 200

    private var orderedPoints: [PickEntryBreakdown.Point] {
        points.sorted { $0.start < $1.start }
    }

    private var maxYValue: Double {
        let maxValue = orderedPoints.map { Double($0.totalItems) }.max() ?? 1
        return max(maxValue * 1.15, 1)
    }

    var body: some View {
        Chart {
            ForEach(orderedPoints) { point in
                ForEach(point.skus) { segment in
                    BarMark(
                        x: .value("Day", point.start, unit: .day),
                        y: .value("Pick Entries", segment.totalItems)
                    )
                    .foregroundStyle(by: .value("SKU", segment.displayLabel))
                    .cornerRadius(5, style: .continuous)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(preset: .automatic) { value in
                if let date = value.as(Date.self) {
                    AxisGridLine()
                    AxisValueLabel {
                        Text(date, format: Date.FormatStyle().month(.abbreviated).day())
                    }
                }
            }
        }
        .chartLegend(showLegend ? .visible : .hidden)
        .chartYScale(domain: 0...maxYValue)
        .frame(height: maxHeight)
    }
}
