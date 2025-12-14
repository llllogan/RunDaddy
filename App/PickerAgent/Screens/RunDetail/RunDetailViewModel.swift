//
//  RunDetailViewModel.swift
//  PickAgent
//
//  Created by ChatGPT on 5/25/2025.
//

import Foundation
import Combine
import SwiftUI

struct CompanyUser: Identifiable, Equatable {
    let id: String
    let email: String
    let firstName: String?
    let lastName: String?
    let phone: String?
    let role: String?
    
    var displayName: String {
        let trimmedFirst = firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedLast = lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if !trimmedFirst.isEmpty && !trimmedLast.isEmpty {
            return "\(trimmedFirst) \(trimmedLast)"
        } else if !trimmedFirst.isEmpty {
            return trimmedFirst
        } else if !trimmedLast.isEmpty {
            return trimmedLast
        } else {
            return email
        }
    }
}

struct RunOverviewSummary: Equatable {
    let runDate: Date
    let runnerName: String?
    let machineCount: Int
    let totalCoils: Int
    let packedCoils: Int
    let remainingCoils: Int
    let totalItems: Int
    let totalWeightGrams: Double
    let itemsMissingWeight: Int
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

struct ColdChestSkuChip: Identifiable, Equatable {
    let id: String
    let label: String
    let count: Int
    let colour: Color
}

@MainActor
final class RunDetailViewModel: ObservableObject {
    @Published private(set) var detail: RunDetail?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var locationSections: [RunLocationSection] = []
    @Published private(set) var companyUsers: [CompanyUser] = []
    @Published private(set) var companyFeatures: CompanyFeatures?
    @Published private(set) var chocolateBoxes: [RunDetail.ChocolateBox] = []
    @Published private(set) var locationOrders: [RunDetail.LocationOrder] = []
    @Published var activePackingSessionId: String?
    @Published private(set) var companyLocation: String?
    @Published private(set) var currentMembershipRole: String?
    @Published private(set) var locationSchedules: [String: LocationSchedule] = [:]
    @Published var noteCount: Int?
    
    // MARK: - Haptic Feedback Triggers
    @Published var resetTrigger = false

    let runId: String
    let session: AuthSession
    let service: RunsServicing
    private let companyService: CompanyServicing
    private let authService: AuthServicing
    private let locationsService: LocationsServicing
    private let notesService: NotesServicing
    private var locationContextsByID: [String: LocationContext] = [:]

    var pendingUnassignedPickItems: [RunDetail.PickItem] {
        guard let detail else { return [] }
        return detail.pickItems.filter { !$0.isPicked }
    }

    init(
        runId: String,
        session: AuthSession,
        service: RunsServicing,
        companyService: CompanyServicing? = nil,
        authService: AuthServicing? = nil,
        locationsService: LocationsServicing? = nil,
        notesService: NotesServicing? = nil
    ) {
        self.runId = runId
        self.session = session
        self.service = service
        self.companyService = companyService ?? CompanyService()
        self.authService = authService ?? AuthService()
        self.locationsService = locationsService ?? LocationsService()
        self.notesService = notesService ?? NotesService()
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
            async let detailTask = service.fetchRunDetail(withId: runId, credentials: session.credentials)
            async let usersTask = service.fetchCompanyUsers(credentials: session.credentials)
            async let chocolateBoxesTask = service.fetchChocolateBoxes(for: runId, credentials: session.credentials)
            async let companyLocationTask = fetchCompanyContext()

            let detail = try await detailTask
            let users = try await usersTask
            let chocolateBoxes = try await chocolateBoxesTask
            let companyContext = await companyLocationTask
            
            self.detail = detail
            self.companyUsers = users
            self.chocolateBoxes = chocolateBoxes.sorted { $0.number < $1.number }
            self.locationOrders = detail.locationOrders.sorted { $0.position < $1.position }
            self.companyLocation = companyContext.location
            self.currentMembershipRole = companyContext.role
            rebuildLocationData(from: detail)
            await refreshLocationSchedules(from: detail.locations)
            Task {
                await self.loadRunNoteCount()
            }
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                errorMessage = runError.localizedDescription
            } else {
                errorMessage = "We couldn't load this run right now. Please try again."
            }
            detail = nil
            companyUsers = []
            locationSections = []
            locationContextsByID = [:]
            locationOrders = []
            locationSchedules = [:]
            noteCount = nil
        }

        isLoading = false
    }
    
    func loadChocolateBoxes() async {
        guard let runId = detail?.id else { return }
        
        do {
            let chocolateBoxes = try await service.fetchChocolateBoxes(for: runId, credentials: session.credentials)
            self.chocolateBoxes = chocolateBoxes.sorted { $0.number < $1.number }
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                errorMessage = runError.localizedDescription
            } else {
                errorMessage = "Failed to load chocolate boxes. Please try again."
            }
        }
    }
    
    func createChocolateBox(number: Int, machineId: String) async {
        guard let runId = detail?.id else { return }
        
        do {
            let newBox = try await service.createChocolateBox(for: runId, number: number, machineId: machineId, credentials: session.credentials)
            chocolateBoxes.append(newBox)
            chocolateBoxes.sort { $0.number < $1.number }
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                errorMessage = runError.localizedDescription
            } else {
                errorMessage = "Failed to create chocolate box. Please try again."
            }
        }
    }
    
    func deleteChocolateBox(boxId: String) async {
        guard let runId = detail?.id else { return }
        
        do {
            try await service.deleteChocolateBox(for: runId, boxId: boxId, credentials: session.credentials)
            chocolateBoxes.removeAll { $0.id == boxId }
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                errorMessage = runError.localizedDescription
            } else {
                errorMessage = "Failed to delete chocolate box. Please try again."
            }
        }
    }

    func startPackingSession(categories: [String?]?) async throws -> PackingSession {
        let session = try await service.createPackingSession(for: runId, categories: categories, credentials: session.credentials)
        activePackingSessionId = session.id
        return session
    }

    func loadActivePackingSession() async {
        let current = activePackingSessionId
        do {
            let session = try await service.fetchActivePackingSession(for: runId, credentials: session.credentials)
            activePackingSessionId = session?.id
        } catch {
            // Keep whatever was previously known on errors; caller can still start a new session explicitly
            activePackingSessionId = current
        }
    }

    func resolveCanBreakDownRun() async -> Bool? {
        if let cached = companyFeatures {
            return cached.features.canBreakDownRun
        }

        guard let companyId = detail?.companyId else {
            return nil
        }

        do {
            let features = try await companyService.fetchFeatures(companyId: companyId, credentials: session.credentials)
            companyFeatures = features
            return features.features.canBreakDownRun
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let companyError = error as? CompanyServiceError {
                errorMessage = companyError.localizedDescription
            } else {
                errorMessage = "We couldn't check your company plan right now. Please try again."
            }
            return nil
        }
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
        var totalWeightGrams = 0.0
        var itemsMissingWeight = 0
        detail.pickItems.forEach { item in
            let count = max(item.count, 0)
            if let weight = item.sku?.weight {
                totalWeightGrams += Double(count) * weight
            } else {
                itemsMissingWeight += count
            }
        }

        return RunOverviewSummary(
            runDate: detail.runDate,
            runnerName: detail.runner?.displayName,
            machineCount: detail.machines.count,
            totalCoils: totalCoils,
            packedCoils: packedCoils,
            remainingCoils: max(totalCoils - packedCoils, 0),
            totalItems: totalItems,
            totalWeightGrams: totalWeightGrams,
            itemsMissingWeight: itemsMissingWeight
        )
    }

    var runColdChestChips: [ColdChestSkuChip] {
        let grouped = Dictionary(grouping: detail?.pickItems ?? []) { item -> String? in
            guard let sku = item.sku, sku.isFreshOrFrozen else { return nil }
            return sku.id
        }

        let chips = grouped.compactMap { key, items -> ColdChestSkuChip? in
            guard let key, let sku = items.first?.sku else { return nil }
            let count = items.reduce(0) { $0 + max($1.count, 0) }
            let colour = ColorCodec.color(fromHex: sku.labelColour) ?? Theme.coldChestTint
            let label = sku.type
            return ColdChestSkuChip(id: key, label: label, count: count, colour: colour)
        }

        return chips.sorted { lhs, rhs in
            lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    var pendingPickItems: [RunDetail.PickItem] {
        detail?.pendingPickItems ?? []
    }
    
    var isRunComplete: Bool {
        guard let detail = detail else { return false }
        let totalCoils = detail.pickItems.count
        guard totalCoils > 0 else { return false }
        
        let packedCoils = detail.pickItems.reduce(into: 0) { partialResult, item in
            if item.isPicked {
                partialResult += 1
            }
        }
        
        return packedCoils >= totalCoils
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

    func pickItemCount(for sectionID: String) -> Int {
        locationContextsByID[sectionID]?.pickItems.count ?? 0
    }

    func coldChestItemCount(for sectionID: String) -> Int {
        guard let context = locationContextsByID[sectionID] else { return 0 }
        return context.pickItems.reduce(into: 0) { total, item in
            guard item.sku?.isFreshOrFrozen == true else { return }
            total += max(item.count, 0)
        }
    }

    func coldChestSkuChips(for sectionID: String) -> [ColdChestSkuChip] {
        guard let context = locationContextsByID[sectionID] else { return [] }

        let grouped = Dictionary(grouping: context.pickItems) { item -> String? in
            guard let sku = item.sku, sku.isFreshOrFrozen else { return nil }
            return sku.id
        }

        let chips = grouped.compactMap { key, items -> ColdChestSkuChip? in
            guard let key, let sku = items.first?.sku else { return nil }
            let count = items.reduce(0) { $0 + max($1.count, 0) }
            let colour = ColorCodec.color(fromHex: sku.labelColour) ?? Theme.coldChestTint
            let label = RunDetailViewModel.buildMonogram(from: sku.type)
            return ColdChestSkuChip(id: key, label: label, count: count, colour: colour)
        }

        return chips.sorted { lhs, rhs in
            lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    static func buildMonogram(from type: String) -> String {
        let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "??"
        }

        let words = trimmed
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        if words.count >= 2 {
            return words.prefix(2).map { word in
                word.prefix(1).uppercased()
            }.joined()
        }

        if let firstWord = words.first, firstWord.count >= 2 {
            return firstWord.prefix(2).uppercased()
        }

        return String(words.first?.prefix(1).uppercased() ?? "?")
    }

    func deletePickEntries(for sectionID: String) async -> Bool {
        guard let runId = detail?.id else { return false }

        do {
            try await service.deletePickEntries(for: runId, locationID: sectionID, credentials: session.credentials)
            await load(force: true)
            return true
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                errorMessage = runError.localizedDescription
            } else {
                errorMessage = "Failed to delete pick entries for this location. Please try again."
            }
            return false
        }
    }

    func assignUser(to role: String) async {
        guard let runId = detail?.id else { return }
        isLoading = true
        errorMessage = nil

        do {
            print("Assigning user \(session.profile.id) to role: \(role) for run: \(runId)")
            try await service.assignUser(to: runId, userId: session.profile.id, role: role, credentials: session.credentials)
            // Reload detail after assignment
            await load(force: true)
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                errorMessage = runError.localizedDescription
            } else {
                errorMessage = "Failed to assign role. Please try again."
            }
        }

        isLoading = false
    }
    
    func assignUser(userId: String, to role: String) async {
        guard let runId = detail?.id else { return }
        isLoading = true
        errorMessage = nil

        do {
            try await service.assignUser(to: runId, userId: userId, role: role, credentials: session.credentials)
            // Reload the detail after assignment
            await load(force: true)
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                errorMessage = runError.localizedDescription
            } else {
                errorMessage = "Failed to assign role. Please try again."
            }
        }

        isLoading = false
    }
    
    func unassignUser(from role: String) async {
        guard let runId = detail?.id else { return }
        isLoading = true
        errorMessage = nil

        do {
            try await service.assignUser(to: runId, userId: "", role: role, credentials: session.credentials)
            // Reload the detail after unassignment
            await load(force: true)
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                errorMessage = runError.localizedDescription
            } else {
                errorMessage = "Failed to unassign role. Please try again."
            }
        }

        isLoading = false
    }
    
    func resetPickStatuses(for pickItems: [RunDetail.PickItem]) async -> Bool {
        let pickedItems = pickItems.filter { $0.isPicked }
        guard !pickedItems.isEmpty else {
            return true
        }

        let targetRunId = detail?.id ?? runId
        errorMessage = nil

        do {
            try await service.updatePickItemStatuses(
                runId: targetRunId,
                pickIds: pickedItems.map { $0.id },
                isPicked: false,
                credentials: session.credentials
            )
            await load(force: true)
            // Trigger haptic feedback for successful reset
            resetTrigger.toggle()
            return true
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                errorMessage = runError.localizedDescription
            } else {
                errorMessage = "We couldn't reset the pick statuses. Please try again."
            }
            return false
        }
    }
    
    func updateRunStatus(to status: String) async {
        guard let runId = detail?.id else { return }
        isLoading = true
        errorMessage = nil

        do {
            try await service.updateRunStatus(runId: runId, status: status, credentials: session.credentials)
            // Reload the detail after status update
            await load(force: true)
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                errorMessage = runError.localizedDescription
            } else {
                errorMessage = "Failed to update run status. Please try again."
            }
        }

        isLoading = false
    }
    
    func updateRunStatusToReadyIfComplete() async {
        guard detail?.id != nil else { return }
        
        // Check if run is 100% complete
        let totalCoils = detail?.pickItems.count ?? 0
        guard totalCoils > 0 else { return }
        
        let packedCoils = detail?.pickItems.reduce(into: 0) { partialResult, item in
            if item.isPicked {
                partialResult += 1
            }
        } ?? 0
        
        if packedCoils >= totalCoils && detail?.status != "READY" {
            await updateRunStatus(to: "READY")
        }
    }

    func loadRunNoteCount() async {
        do {
            let response = try await notesService.fetchNotes(
                runId: runId,
                includePersistentForRun: true,
                recentDays: nil,
                limit: 1,
                credentials: session.credentials
            )
            noteCount = response.total
        } catch {
            noteCount = nil
        }
    }

    func saveLocationOrder(with orderedLocationIds: [String?]) async throws {
        guard let runId = detail?.id else {
            throw RunsServiceError.runNotFound
        }

        guard !orderedLocationIds.isEmpty else {
            errorMessage = "There aren't any locations to reorder yet."
            throw RunsServiceError.invalidLocationOrder
        }

        do {
            _ = try await service.updateLocationOrder(for: runId, orderedLocationIds: orderedLocationIds, credentials: session.credentials)
            // After successfully saving to DB, reload entire run detail from server to ensure consistency
            await load(force: true)
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                errorMessage = runError.localizedDescription
            } else {
                errorMessage = "We couldn't update the location order. Please try again."
            }
            throw error
        }
    }

    private struct LocationContext {
        var section: RunLocationSection
        var machines: [String: RunDetail.Machine]
        var pickItems: [RunDetail.PickItem]
    }

    struct LocationSchedule: Equatable {
        let address: String?
        let openingMinutes: Int?
        let closingMinutes: Int?
        let dwellMinutes: Int?
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

        let orderingLookup = locationOrders.reduce(into: [String: Int]()) { partialResult, order in
            let key = order.locationId ?? RunLocationSection.unassignedIdentifier
            partialResult[key] = order.position
        }

        let sortedSections = contexts.map { $0.1.section }
            .sorted { lhs, rhs in
                let lhsOrder = orderingLookup[lhs.id]
                let rhsOrder = orderingLookup[rhs.id]

                switch (lhsOrder, rhsOrder) {
                case let (.some(left), .some(right)):
                    if left == right {
                        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                    }
                    return left < right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }

        locationSections = sortedSections
        locationContextsByID = Dictionary(uniqueKeysWithValues: contexts.map { ($0.0, $0.1) })
    }

    func schedule(for locationId: String?) -> LocationSchedule? {
        guard let locationId, !locationId.isEmpty else { return nil }
        return locationSchedules[locationId]
    }

    private func refreshLocationSchedules(from locations: [RunDetail.Location]) async {
        let baseSchedules: [String: LocationSchedule] = Dictionary(uniqueKeysWithValues: locations.map { location in
            let normalizedAddress = location.address?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                location.id,
                LocationSchedule(
                    address: normalizedAddress?.isEmpty == true ? nil : normalizedAddress,
                    openingMinutes: location.openingTimeMinutes,
                    closingMinutes: location.closingTimeMinutes,
                    dwellMinutes: location.dwellTimeMinutes
                )
            )
        })

        locationSchedules = baseSchedules

        let fetchedSchedules = await fetchLocationDetails(for: locations)
        if !fetchedSchedules.isEmpty {
            locationSchedules.merge(fetchedSchedules) { _, new in new }
        }
    }

    private func fetchLocationDetails(for locations: [RunDetail.Location]) async -> [String: LocationSchedule] {
        var result: [String: LocationSchedule] = [:]

        for location in locations {
            do {
                let response = try await locationsService.getLocation(id: location.id)
                let normalizedAddress = response.address?.trimmingCharacters(in: .whitespacesAndNewlines)
                result[response.id] = LocationSchedule(
                    address: normalizedAddress?.isEmpty == true ? nil : normalizedAddress,
                    openingMinutes: response.openingTimeMinutes,
                    closingMinutes: response.closingTimeMinutes,
                    dwellMinutes: response.dwellTimeMinutes
                )
            } catch {
                continue
            }
        }

        return result
    }

    private func fetchCompanyContext() async -> (location: String?, role: String?) {
        do {
            let profile = try await authService.fetchCurrentUserProfile(credentials: session.credentials)
            let location = profile.currentCompany?.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedLocation = (location?.isEmpty == true) ? nil : location
            let role = profile.currentCompany?.role.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedRole = (role?.isEmpty == true) ? nil : role
            return (normalizedLocation, normalizedRole)
        } catch {
            return (companyLocation, currentMembershipRole)
        }
    }
}
