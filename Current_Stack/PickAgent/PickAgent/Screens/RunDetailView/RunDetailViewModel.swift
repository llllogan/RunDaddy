//
//  RunDetailViewModel.swift
//  PickAgent
//
//  Created by ChatGPT on 5/25/2025.
//

import Foundation
import Combine

struct RunOverviewSummary: Equatable {
    let runDate: Date
    let runnerName: String?
    let machineCount: Int
    let totalCoils: Int
    let packedCoils: Int
    let remainingCoils: Int
    let totalItems: Int
}

struct RunLocationSection: Identifiable, Equatable {
    static let unassignedIdentifier = "_unassigned"

    let id: String
    let location: RunDetail.Location?
    let machineCount: Int
    let totalCoils: Int
    let packedCoils: Int
    let totalItems: Int

    var title: String {
        let trimmed = location?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unassigned Location" : trimmed
    }

    var subtitle: String? {
        guard let raw = location?.address else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var remainingCoils: Int {
        max(totalCoils - packedCoils, 0)
    }

    var hasAddress: Bool {
        subtitle != nil
    }
}

@MainActor
final class RunDetailViewModel: ObservableObject {
    @Published private(set) var detail: RunDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let runId: String
    private let session: AuthSession
    private let service: RunsServicing

    init(runId: String, session: AuthSession, service: RunsServicing) {
        self.runId = runId
        self.session = session
        self.service = service
    }

    func load(force: Bool = false) async {
        if isLoading && !force {
            return
        }

        isLoading = true
        if !force {
            errorMessage = nil
        }

        do {
            let detail = try await service.fetchRunDetail(withId: runId, credentials: session.credentials)
            self.detail = detail
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                errorMessage = runError.localizedDescription
            } else {
                errorMessage = "We couldn't load this run right now. Please try again."
            }
            detail = nil
        }

        isLoading = false
    }

    var overview: RunOverviewSummary? {
        guard let detail else { return nil }

        let totalCoils = detail.pickItems.count
        let packedCoils = detail.pickItems.reduce(into: 0) { partialResult, item in
            if item.isPicked {
                partialResult += 1
            }
        }
        let totalItems = detail.pickItems.reduce(into: 0) { partialResult, item in
            partialResult += max(item.count, 0)
        }

        return RunOverviewSummary(
            runDate: detail.runDate,
            runnerName: detail.runner?.displayName,
            machineCount: detail.machines.count,
            totalCoils: totalCoils,
            packedCoils: packedCoils,
            remainingCoils: max(totalCoils - packedCoils, 0),
            totalItems: totalItems
        )
    }

    var locationSections: [RunLocationSection] {
        guard let detail else { return [] }
        return buildLocationSections(from: detail)
    }

    private struct LocationAccumulator {
        var location: RunDetail.Location?
        var machineIds: Set<String>
        var totalCoils: Int
        var packedCoils: Int
        var totalItems: Int
    }

    private func buildLocationSections(from detail: RunDetail) -> [RunLocationSection] {
        var accumulators: [String: LocationAccumulator] = [:]

        func key(for location: RunDetail.Location?) -> String {
            location?.id ?? RunLocationSection.unassignedIdentifier
        }

        for location in detail.locations {
            let locationKey = key(for: location)
            accumulators[locationKey] = LocationAccumulator(
                location: location,
                machineIds: [],
                totalCoils: 0,
                packedCoils: 0,
                totalItems: 0
            )
        }

        for machine in detail.machines {
            let locationKey = key(for: machine.location)
            var accumulator = accumulators[locationKey] ?? LocationAccumulator(
                location: machine.location,
                machineIds: [],
                totalCoils: 0,
                packedCoils: 0,
                totalItems: 0
            )
            accumulator.machineIds.insert(machine.id)
            accumulators[locationKey] = accumulator
        }

        for item in detail.pickItems {
            let locationKey = key(for: item.location ?? item.machine?.location)
            var accumulator = accumulators[locationKey] ?? LocationAccumulator(
                location: item.location ?? item.machine?.location,
                machineIds: [],
                totalCoils: 0,
                packedCoils: 0,
                totalItems: 0
            )

            if let machineId = item.machine?.id {
                accumulator.machineIds.insert(machineId)
            }

            accumulator.totalCoils += 1
            accumulator.totalItems += max(item.count, 0)
            if item.isPicked {
                accumulator.packedCoils += 1
            }

            accumulators[locationKey] = accumulator
        }

        return accumulators.values
            .map { accumulator in
                let id = accumulator.location?.id ?? RunLocationSection.unassignedIdentifier
                return RunLocationSection(
                    id: id,
                    location: accumulator.location,
                    machineCount: accumulator.machineIds.count,
                    totalCoils: accumulator.totalCoils,
                    packedCoils: accumulator.packedCoils,
                    totalItems: accumulator.totalItems
                )
            }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }
}
