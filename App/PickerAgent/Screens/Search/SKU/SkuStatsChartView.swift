import SwiftUI
import Charts

struct SkuStatsChartView: View {
    let breakdown: PickEntryBreakdown?
    let availableFilters: PickEntryBreakdown.AvailableFilters
    let isLoading: Bool
    let errorMessage: String?
    @Binding var selectedPeriod: SkuPeriod
    @Binding var selectedLocationFilter: String?
    @Binding var selectedMachineFilter: String?
    let onFilterChange: (_ locationId: String?, _ machineId: String?) async -> Void

    private var aggregation: PickEntryBreakdown.Aggregation { selectedPeriod.pickEntryAggregation }
    private var calendar: Calendar { chartCalendar(for: timeZone) }
    private var timeZone: String { breakdown?.timeZone ?? TimeZone.current.identifier }

    private var locationOptions: [PickEntryBreakdown.FilterOption] { availableFilters.location }
    private var machineOptions: [PickEntryBreakdown.FilterOption] { availableFilters.machine }

    private var breakdownPoints: [PickEntryBreakdown.Point] {
        let points = breakdown?.points ?? []
        guard aggregation == .week else { return points.sorted { $0.start < $1.start } }
        return ensureRollingEightDayWindow(points: points, calendar: calendar)
    }

    private var averages: [PickEntryBreakdown.WeekAverage] {
        breakdown?.weekAverages ?? []
    }

    private var hasChartData: Bool {
        breakdownPoints.contains { !$0.skus.isEmpty && $0.totalItems > 0 }
    }

    private var chartSkuCount: Int {
        let skuIds = breakdownPoints.flatMap { point in
            point.skus.map(\.skuId)
        }
        return Set(skuIds).count
    }

    private var shouldHideLegend: Bool {
        chartSkuCount > 6
    }

    private var locationFilterLabel: String {
        guard let selectedLocationFilter,
              let option = locationOptions.first(where: { $0.id == selectedLocationFilter }) else {
            return "All Locations"
        }
        return option.displayName
    }

    private var machineFilterLabel: String {
        guard let selectedMachineFilter,
              let option = machineOptions.first(where: { $0.id == selectedMachineFilter }) else {
            return "All Machines"
        }
        return option.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Picks per ")
                    Menu {
                        ForEach(SkuPeriod.allCases) { period in
                            Button(action: { selectedPeriod = period }) {
                                HStack {
                                    Text(period.displayName)
                                    if selectedPeriod == period {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        filterChip(label: selectedPeriod.displayName)
                    }
                    .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
            }

            filterControls

            if isLoading && breakdownPoints.isEmpty {
                ProgressView("Loading")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let errorMessage, breakdownPoints.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if hasChartData {
                PickEntryBarChart(
                    points: breakdownPoints,
                    aggregation: aggregation,
                    weekAverages: averages,
                    timeZoneIdentifier: timeZone,
                    showLegend: !shouldHideLegend,
                    maxHeight: 220
                )
            } else {
                Text("No data is available for the selected period.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
        .onChange(of: locationOptions) { _, _ in
            guard let selection = selectedLocationFilter else { return }
            if locationOptions.first(where: { $0.id == selection }) == nil {
                selectedLocationFilter = nil
                selectedMachineFilter = nil
                applyFilters(locationId: nil, machineId: nil)
            }
        }
        .onChange(of: machineOptions) { _, _ in
            guard let selection = selectedMachineFilter else { return }
            if machineOptions.first(where: { $0.id == selection }) == nil {
                selectedMachineFilter = nil
                applyFilters(locationId: selectedLocationFilter, machineId: nil)
            }
        }
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    Button("All Locations") {
                        applyFilters(locationId: nil, machineId: selectedMachineFilter)
                    }
                    ForEach(locationOptions) { option in
                        Button(action: {
                            applyFilters(locationId: option.id, machineId: nil)
                        }) {
                            HStack {
                                Text(option.displayName)
                                if selectedLocationFilter == option.id && selectedMachineFilter == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChip(label: locationFilterLabel)
                }

                Menu {
                    Button("All Machines") {
                        applyFilters(locationId: selectedLocationFilter, machineId: nil)
                    }
                    ForEach(machineOptions) { machine in
                        Button(action: {
                            applyFilters(locationId: selectedLocationFilter, machineId: machine.id)
                        }) {
                            HStack {
                                Text(machine.displayName)
                                if selectedMachineFilter == machine.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChip(label: machineFilterLabel)
                }
                .disabled(machineOptions.isEmpty)
            }
            .foregroundStyle(.secondary)
            .font(.subheadline)
        }
    }

    private func applyFilters(locationId: String?, machineId: String?) {
        Task {
            await onFilterChange(locationId, machineId)
        }
    }
}
