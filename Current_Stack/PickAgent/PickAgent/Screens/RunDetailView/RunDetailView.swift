//
//  RunDetailView.swift
//  PickAgent
//
//  Created by ChatGPT on 5/25/2025.
//

import SwiftUI

struct RunDetailView: View {
    @StateObject private var viewModel: RunDetailViewModel

    init(runId: String, session: AuthSession, service: RunsServicing = RunsService()) {
        _viewModel = StateObject(wrappedValue: RunDetailViewModel(runId: runId, session: session, service: service))
    }

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.overview == nil {
                Section {
                    LoadingRow()
                }
            }

            if let message = viewModel.errorMessage {
                Section {
                    ErrorRow(message: message)
                }
            }

            if let overview = viewModel.overview {
                Section {
                    RunOverviewBento(summary: overview)
                        .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } header: {
                    Text("Run Overview")
                }
            }

            Section("Locations") {
                if viewModel.locationSections.isEmpty {
                    Text("No locations are assigned to this run yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(viewModel.locationSections) { section in
                        if let locationDetail = viewModel.locationDetail(for: section.id) {
                            NavigationLink {
                                LocationDetailView(detail: locationDetail)
                            } label: {
                                LocationSummaryRow(section: section)
                            }
                        } else {
                            LocationSummaryRow(section: section)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Run Details")
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load(force: true)
        }
    }
}

private struct LocationSummaryRow: View {
    let section: RunLocationSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.headline)
                .fontWeight(.semibold)

            if let subtitle = section.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label("\(section.machineCount) \(section.machineCount == 1 ? "Machine" : "Machines")", systemImage: "building.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(section.totalCoils) coils", systemImage: "scope")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if section.remainingCoils > 0 {
                    Label("\(section.remainingCoils) remaining", systemImage: "cart")
                        .font(.caption)
                        .foregroundStyle(.pink)
                } else {
                    Label("All packed", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 6)
    }
}

private struct LoadingRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading run…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ErrorRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    struct PreviewRunsService: RunsServicing {
        func fetchRuns(for schedule: RunsSchedule, credentials: AuthCredentials) async throws -> [RunSummary] {
            []
        }

        func fetchRunDetail(withId runId: String, credentials: AuthCredentials) async throws -> RunDetail {
            let downtown = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
            let uptown = RunDetail.Location(id: "loc-2", name: "Uptown Annex", address: "456 Oak Avenue")

            let snackType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
            let drinkType = RunDetail.MachineTypeDescriptor(id: "type-2", name: "Drink Machine", description: nil)

            let machineA = RunDetail.Machine(id: "machine-1", code: "A-101", description: "Lobby", machineType: snackType, location: downtown)
            let machineB = RunDetail.Machine(id: "machine-2", code: "B-204", description: "Breakroom", machineType: snackType, location: downtown)
            let machineC = RunDetail.Machine(id: "machine-3", code: "C-08", description: "Front Vestibule", machineType: drinkType, location: uptown)

            let coilA = RunDetail.Coil(id: "coil-1", code: "C1", machineId: machineA.id)
            let coilB = RunDetail.Coil(id: "coil-2", code: "C2", machineId: machineB.id)
            let coilC = RunDetail.Coil(id: "coil-3", code: "C3", machineId: machineC.id)

            let coilItemA = RunDetail.CoilItem(id: "coil-item-1", par: 10, coil: coilA)
            let coilItemB = RunDetail.CoilItem(id: "coil-item-2", par: 8, coil: coilB)
            let coilItemC = RunDetail.CoilItem(id: "coil-item-3", par: 12, coil: coilC)

            let skuSnack = RunDetail.Sku(id: "sku-1", code: "SKU-001", name: "Trail Mix", type: "Snack", isCheeseAndCrackers: false)
            let skuDrink = RunDetail.Sku(id: "sku-2", code: "SKU-002", name: "Sparkling Water", type: "Beverage", isCheeseAndCrackers: false)

            let pickA = RunDetail.PickItem(id: "pick-1", count: 6, status: "PICKED", pickedAt: Date(), coilItem: coilItemA, sku: skuSnack, machine: machineA, location: downtown)
            let pickB = RunDetail.PickItem(id: "pick-2", count: 4, status: "PENDING", pickedAt: nil, coilItem: coilItemB, sku: skuSnack, machine: machineB, location: downtown)
            let pickC = RunDetail.PickItem(id: "pick-3", count: 9, status: "PICKED", pickedAt: Date().addingTimeInterval(-1200), coilItem: coilItemC, sku: skuDrink, machine: machineC, location: uptown)

            let chocolateBox = RunDetail.ChocolateBox(id: "box-1", number: 1, machine: machineA)

            return RunDetail(
                id: runId,
                status: "PICKING",
                companyId: "company-1",
                scheduledFor: Date().addingTimeInterval(3600),
                pickingStartedAt: Date().addingTimeInterval(-1800),
                pickingEndedAt: nil,
                createdAt: Date().addingTimeInterval(-7200),
                picker: RunParticipant(id: "picker-1", firstName: "Jordan", lastName: "Smith"),
                runner: RunParticipant(id: "runner-1", firstName: "Avery", lastName: "Lee"),
                locations: [downtown, uptown],
                machines: [machineA, machineB, machineC],
                pickItems: [pickA, pickB, pickC],
                chocolateBoxes: [chocolateBox]
            )
        }
    }

    let credentials = AuthCredentials(
        accessToken: "preview-token",
        refreshToken: "preview-refresh",
        userID: "user-1",
        expiresAt: Date().addingTimeInterval(3600)
    )
    let profile = UserProfile(
        id: "user-1",
        email: "jordan@example.com",
        firstName: "Jordan",
        lastName: "Smith",
        phone: nil,
        role: "PICKER"
    )
    let session = AuthSession(credentials: credentials, profile: profile)

    return NavigationStack {
        RunDetailView(runId: "run-12345", session: session, service: PreviewRunsService())
    }
}
