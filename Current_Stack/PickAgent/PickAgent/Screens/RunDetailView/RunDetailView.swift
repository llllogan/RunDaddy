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
                        LocationSummaryRow(section: section)
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
            let location = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
            let machineType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
            let machine = RunDetail.Machine(id: "machine-1", code: "A-101", description: "Lobby", machineType: machineType, location: location)
            let coil = RunDetail.Coil(id: "coil-1", code: "C1", machineId: machine.id)
            let coilItem = RunDetail.CoilItem(id: "coil-item-1", par: 10, coil: coil)
            let sku = RunDetail.Sku(id: "sku-1", code: "SKU-001", name: "Trail Mix", type: "Snack", isCheeseAndCrackers: false)
            let pickItem = RunDetail.PickItem(id: "pick-1", count: 6, status: "PICKED", pickedAt: Date(), coilItem: coilItem, sku: sku, machine: machine, location: location)
            let chocolateBox = RunDetail.ChocolateBox(id: "box-1", number: 1, machine: machine)

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
                locations: [location],
                machines: [machine],
                pickItems: [pickItem],
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
