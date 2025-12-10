//
//  TopLocationsChartView.swift
//  PickAgent
//
//  Created by ChatGPT on 5/25/2025.
//

import SwiftUI
import Charts

struct TopLocationsChartView: View {
    @ObservedObject private var viewModel: ChartsViewModel
    let refreshTrigger: Bool
    @State private var selectedRange: RangeOption
    private let showRangePicker: Bool

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

    init(viewModel: ChartsViewModel, refreshTrigger: Bool = false, showRangePicker: Bool = true) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.refreshTrigger = refreshTrigger
        self.showRangePicker = showRangePicker
        _selectedRange = State(initialValue: .month)
    }

    private var lookbackDescription: String {
        let days = viewModel.topLocationsLookbackDays
        if days <= 1 {
            return "Showing activity from the last day"
        }
        return "Showing activity from the last \(days) days"
    }

    private var totalItemsText: String {
        let total = viewModel.topLocations.reduce(0) { $0 + $1.totalItems }
        if total == 0 {
            return "No packed items in this range"
        }
        if total == 1 {
            return "1 item packed"
        }
        return "\(total) items packed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Group {
                if viewModel.isLoadingTopLocations && viewModel.topLocations.isEmpty {
                    ChartLoadingView(height: 220)
                } else if let error = viewModel.topLocationsError {
                    errorView(message: error)
                } else if viewModel.topLocations.isEmpty {
                    emptyStateView
                } else {
                    chart
                        .chartLoadingOverlay(isPresented: viewModel.isLoadingTopLocations)
                }
            }
        }
        .padding()
        .task {
            await viewModel.loadTopLocations()
        }
        .refreshable {
            await viewModel.refreshTopLocations()
        }
        .onAppear {
            syncSelectedRange(with: viewModel.topLocationsLookbackDays)
        }
        .onChange(of: viewModel.topLocationsLookbackDays) { _, newValue in
            syncSelectedRange(with: newValue)
        }
        .onChange(of: refreshTrigger) { _, _ in
            Task {
                await viewModel.refreshTopLocations()
            }
        }
    }

    private var header: some View {
        Group {
            if showRangePicker {
                HStack(spacing: 2) {
                    Text("Totals for the last ")
                    Menu {
                        ForEach(RangeOption.allCases) { range in
                            Button {
                                selectedRange = range
                                viewModel.updateTopLocationsLookbackDays(range.rawValue)
                            } label: {
                                HStack {
                                    Text(range.label)
                                    if range == selectedRange {
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
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        Chart {
            ForEach(viewModel.topLocations) { location in
                ForEach(location.machines) { machine in
                    BarMark(
                        x: .value("Location", location.locationName),
                        y: .value("Items", machine.totalItems)
                    )
                    .foregroundStyle(by: .value("Machine", machine.displayName))
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: viewModel.topLocations.map(\.locationName)) { value in
                AxisValueLabel {
                    if let stringValue = value.as(String.self) {
                        Text(stringValue)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .frame(height: 240)
        .padding(.top)
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load locations")
                .font(.subheadline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task {
                    await viewModel.refreshTopLocations()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No packed items in this range")
                .font(.subheadline)
            Text("Try expanding the lookback window to include more history.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func syncSelectedRange(with days: Int) {
        if let matching = RangeOption.allCases.min(by: { abs($0.rawValue - days) < abs($1.rawValue - days) }) {
            selectedRange = matching
        }
    }
}
