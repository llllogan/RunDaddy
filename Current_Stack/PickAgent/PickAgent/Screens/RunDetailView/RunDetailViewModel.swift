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

struct RunLocationDetail: Equatable {
    let section: RunLocationSection
    let machines: [RunDetail.Machine]
    let pickItemsByMachine: [String: [RunDetail.PickItem]]

    var pickItems: [RunDetail.PickItem] {
        pickItemsByMachine.values.flatMap { $0 }
    }

    func pickItems(for machine: RunDetail.Machine) -> [RunDetail.PickItem] {
        pickItemsByMachine[machine.id] ?? []
    }
}

@MainActor
final class RunDetailViewModel: ObservableObject {
    @Published private(set) var detail: RunDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var locationSections: [RunLocationSection] = []

    private let runId: String
    private let session: AuthSession
    private let service: RunsServicing
    private var locationContextsByID: [String: LocationContext] = [:]

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
            rebuildLocationData(from: detail)
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                errorMessage = runError.localizedDescription
            } else {
                errorMessage = "We couldn't load this run right now. Please try again."
            }
            detail = nil
            locationSections = []
            locationContextsByID = [:]
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

    func locationDetail(for sectionID: String) -> RunLocationDetail? {
        guard let context = locationContextsByID[sectionID] else {
            return nil
        }

        let machines = context.machines.values.sorted { lhs, rhs in
            lhs.code.localizedCaseInsensitiveCompare(rhs.code) == .orderedAscending
        }

        var byMachine: [String: [RunDetail.PickItem]] = Dictionary(uniqueKeysWithValues: machines.map { ($0.id, []) })
        for item in context.pickItems {
            guard let machineId = item.machine?.id else { continue }
            byMachine[machineId, default: []].append(item)
        }

        return RunLocationDetail(section: context.section, machines: machines, pickItemsByMachine: byMachine)
    }

    private struct LocationContext {
        var section: RunLocationSection
        var machines: [String: RunDetail.Machine]
        var pickItems: [RunDetail.PickItem]
    }

    private struct LocationContextBuilder {
        var location: RunDetail.Location?
        var machines: [String: RunDetail.Machine] = [:]
        var pickItems: [RunDetail.PickItem] = []
    }

    private func rebuildLocationData(from detail: RunDetail) {
        var builders: [String: LocationContextBuilder] = [:]

        func key(for location: RunDetail.Location?) -> String {
            location?.id ?? RunLocationSection.unassignedIdentifier
        }

        for location in detail.locations {
            let locationKey = key(for: location)
            var builder = builders[locationKey] ?? LocationContextBuilder(location: location)
            builder.location = location
            builders[locationKey] = builder
        }

        for machine in detail.machines {
            let locationKey = key(for: machine.location)
            var builder = builders[locationKey] ?? LocationContextBuilder(location: machine.location)
            builder.machines[machine.id] = machine
            builders[locationKey] = builder
        }

        for item in detail.pickItems {
            let locationKey = key(for: item.location ?? item.machine?.location)
            var builder = builders[locationKey] ?? LocationContextBuilder(location: item.location ?? item.machine?.location)
            builder.pickItems.append(item)
            if let machine = item.machine {
                builder.machines[machine.id] = machine
            }
            builders[locationKey] = builder
        }

        let contexts: [(String, LocationContext)] = builders.map { key, builder in
            let machines = Array(builder.machines.values)
            let totalCoils = builder.pickItems.count
            let packedCoils = builder.pickItems.reduce(into: 0) { partialResult, item in
                if item.isPicked {
                    partialResult += 1
                }
            }
            let totalItems = builder.pickItems.reduce(0) { $0 + max($1.count, 0) }

            let section = RunLocationSection(
                id: key,
                location: builder.location,
                machineCount: machines.count,
                totalCoils: totalCoils,
                packedCoils: packedCoils,
                totalItems: totalItems
            )

            let context = LocationContext(
                section: section,
                machines: builder.machines,
                pickItems: builder.pickItems
            )
            return (key, context)
        }

        let sortedSections = contexts.map { $0.1.section }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        locationSections = sortedSections
        locationContextsByID = Dictionary(uniqueKeysWithValues: contexts.map { ($0.0, $0.1) })
    }
}
