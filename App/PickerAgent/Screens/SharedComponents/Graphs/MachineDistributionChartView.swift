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
            header

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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Share of pick entries by machine")
                .font(.subheadline)
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
