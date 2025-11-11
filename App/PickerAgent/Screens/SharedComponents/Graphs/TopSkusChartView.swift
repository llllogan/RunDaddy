//
//  TopSkusChartView.swift
//  PickAgent
//
//  Created by ChatGPT on 2/14/2026.
//

import SwiftUI
import Charts

struct TopSkusChartView: View {
    @ObservedObject private var viewModel: ChartsViewModel
    let refreshTrigger: Bool

    @State private var selectedLocationFilter: String?
    @State private var selectedMachineFilter: String?

    init(viewModel: ChartsViewModel, refreshTrigger: Bool = false) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.refreshTrigger = refreshTrigger
    }

    private var stats: TopSkuStats? {
        viewModel.topSkuStats
    }

    private var locationOptions: [TopSkuStats.LocationOption] {
        stats?.locations ?? []
    }

    private var machineOptions: [TopSkuStats.MachineOption] {
        stats?.machines ?? []
    }

    private var visibleMachines: [TopSkuStats.MachineOption] {
        guard let locationId = selectedLocationFilter else {
            return machineOptions
        }
        return machineOptions.filter { $0.locationId == locationId }
    }

    private var locationFilterLabel: String {
        guard let filter = selectedLocationFilter,
              let location = locationOptions.first(where: { $0.id == filter }) else {
            return "All Locations"
        }
        return location.displayName
    }

    private var machineFilterLabel: String {
        guard let filter = selectedMachineFilter,
              let machine = machineOptions.first(where: { $0.id == filter }) else {
            return "All Machines"
        }
        return machine.displayName
    }

    private var currentSkus: [TopSkuStats.Sku] {
        stats?.skus ?? []
    }

    private var lookbackDescription: String {
        guard let stats else {
            return "Past year"
        }
        if stats.lookbackDays >= 365 {
            return "Past year"
        }
        return "Last \(stats.lookbackDays) days"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            filterControls

            Group {
                if viewModel.isLoadingTopSkus && currentSkus.isEmpty {
                    loadingView
                } else if let error = viewModel.topSkusError {
                    errorView(message: error)
                } else if currentSkus.isEmpty {
                    emptyStateView
                } else if let stats {
                    chart(for: stats)
                } else {
                    loadingView
                }
            }

            footer
        }
        .padding()
        .task {
            await loadInitialData()
        }
        .refreshable {
            await viewModel.loadTopSkus(locationId: selectedLocationFilter, machineId: selectedMachineFilter)
        }
        .onChange(of: refreshTrigger) { _, _ in
            Task {
                await viewModel.loadTopSkus(locationId: selectedLocationFilter, machineId: selectedMachineFilter)
            }
        }
        .onChange(of: locationOptions) { _, _ in
            guard let selection = selectedLocationFilter else { return }
            if locationOptions.first(where: { $0.id == selection }) == nil {
                selectedLocationFilter = nil
                selectedMachineFilter = nil
                Task {
                    await viewModel.loadTopSkus(locationId: nil, machineId: nil)
                }
            }
        }
        .onChange(of: machineOptions) { _, _ in
            guard let selection = selectedMachineFilter else { return }
            if machineOptions.first(where: { $0.id == selection }) == nil {
                selectedMachineFilter = nil
                Task {
                    await viewModel.loadTopSkus(locationId: selectedLocationFilter, machineId: nil)
                }
            }
        }
    }

    @ViewBuilder
    private var filterControls: some View {
        HStack {
            Menu {
                Button("All Locations") {
                    guard selectedLocationFilter != nil else { return }
                    selectedLocationFilter = nil
                    selectedMachineFilter = nil
                    Task { await applyFilters(locationId: nil, machineId: nil) }
                }
                if !locationOptions.isEmpty {
                    Divider()
                    ForEach(locationOptions) { location in
                        Button(location.displayName) {
                            guard selectedLocationFilter != location.id else { return }
                            selectedMachineFilter = nil
                            selectedLocationFilter = location.id
                            Task { await applyFilters(locationId: location.id, machineId: nil) }
                        }
                    }
                }
            } label: {
                filterChip(label: locationFilterLabel, systemImage: "mappin.and.ellipse")
            }

            Menu {
                Button("All Machines") {
                    guard selectedMachineFilter != nil else { return }
                    selectedMachineFilter = nil
                    Task { await applyFilters(locationId: selectedLocationFilter, machineId: nil) }
                }
                let machines = visibleMachines
                if !machines.isEmpty {
                    Divider()
                    ForEach(machines) { machine in
                        Button(machine.displayName) {
                            guard selectedMachineFilter != machine.id else { return }
                            selectedMachineFilter = machine.id
                            Task { await applyFilters(locationId: selectedLocationFilter, machineId: machine.id) }
                        }
                    }
                }
            } label: {
                filterChip(label: machineFilterLabel, systemImage: "building.2")
            }
            .disabled(visibleMachines.isEmpty && machineOptions.isEmpty)

            Spacer()
        }
    }

    @ViewBuilder
    private func chart(for stats: TopSkuStats) -> some View {
        Chart {
            ForEach(stats.skus) { sku in
                BarMark(
                    x: .value("Picks", sku.totalPicked),
                    y: .value("SKU", sku.skuCode)
                )
                .annotation(position: .trailing) {
                    Text("\(sku.totalPicked)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .chartXAxisLabel("Items picked")
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: max(220, Double(stats.skus.count) * 32.0 + 80))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let stats {
                if stats.totalPicked > 0 {
                    Text("Total picked: \(stats.totalPicked)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        .frame(height: 160)
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load SKUs")
                .font(.subheadline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await applyFilters(locationId: selectedLocationFilter, machineId: selectedMachineFilter) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No picked SKUs yet")
                .font(.subheadline)
            Text("We will show the most active SKUs once picking begins in this window.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func filterChip(label: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray5))
        .clipShape(Capsule())
    }

    private func loadInitialData() async {
        if stats == nil {
            await viewModel.loadTopSkus(locationId: selectedLocationFilter, machineId: selectedMachineFilter)
        }
    }

    private func applyFilters(locationId: String?, machineId: String?) async {
        await viewModel.loadTopSkus(locationId: locationId, machineId: machineId)
    }
}
