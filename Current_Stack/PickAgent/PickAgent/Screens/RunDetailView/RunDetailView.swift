//
//  RunDetailView.swift
//  PickAgent
//
//  Created by ChatGPT on 5/25/2025.
//

import SwiftUI

struct RunDetailView: View {
    @StateObject private var viewModel: RunDetailViewModel
    @State private var showingPackingSession = false
    @State private var showingLocationOrderSheet = false

    init(runId: String, session: AuthSession, service: RunsServicing = RunsService()) {
        _viewModel = StateObject(wrappedValue: RunDetailViewModel(runId: runId, session: session, service: service))
    }

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.overview == nil {
                Section {
                    LoadingRow()
                }
            } else {
                if let overview = viewModel.overview {
                    Section {
                        RunOverviewBento(summary: overview, viewModel: viewModel, assignAction: { role in
                            Task {
                                await viewModel.assignUser(to: role)
                            }
                        })
                            .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0))
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
                                    LocationDetailView(
                                        detail: locationDetail,
                                        runId: viewModel.detail?.id ?? "",
                                        session: viewModel.session,
                                        service: viewModel.service,
                                        viewModel: viewModel,
                                        onPickStatusChanged: {
                                            await viewModel.load(force: true)
                                        }
                                    )
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

            if let message = viewModel.errorMessage {
                Section {
                    ErrorRow(message: message)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingLocationOrderSheet = true
                } label: {
                    Label("Reorder", systemImage: "list.number")
                }
                .disabled(viewModel.locationSections.count < 2)
            }
            
            ToolbarItem(placement: .bottomBar) {
                Button("Start Packing", systemImage: "play") {
                    showingPackingSession = true
                }
                .labelStyle(.titleOnly)
                .fullScreenCover(isPresented: $showingPackingSession) {
                    PackingSessionSheet(runId: viewModel.detail?.id ?? "", session: viewModel.session)
                }
            }
        }
        .sheet(isPresented: $showingLocationOrderSheet) {
            ReorderLocationsSheet(
                viewModel: viewModel,
                sections: viewModel.locationSections
            )
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
            
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(section.machineCount) \(section.machineCount == 1 ? "Machine" : "Machines")")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(.secondary)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
                
                if section.remainingCoils > 0 {
                    Text("\(section.remainingCoils) remaining")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(.secondary)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                } else {
                    Text("All packed")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(.green)
                        .background(Color(.green.opacity(0.15)))
                        .clipShape(Capsule())
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

private struct ReorderLocationsSheet: View {
    @ObservedObject var viewModel: RunDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftSections: [RunLocationSection]
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(viewModel: RunDetailViewModel, sections: [RunLocationSection]) {
        self.viewModel = viewModel
        _draftSections = State(initialValue: sections)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if draftSections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "mappin")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No locations to reorder yet.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section(footer: footer) {
                            ForEach(draftSections) { section in
                                HStack(spacing: 12) {
                                    Image(systemName: "line.3.horizontal")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(section.title)
                                            .font(.body)
                                            .fontWeight(.semibold)
                                        if let subtitle = section.subtitle {
                                            Text(subtitle)
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .onMove { indices, newOffset in
                                draftSections.move(fromOffsets: indices, toOffset: newOffset)
                            }
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                    .disabled(isSaving)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .navigationTitle("Reorder Locations")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await persistChanges()
                        }
                    }
                    .disabled(isSaving || draftSections.count < 2)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Saving")
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var footer: some View {
        Text("Drag the handle to control which locations appear first in the run detail and voice prompts.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }

    private func persistChanges() async {
        guard draftSections.count >= 1 else {
            dismiss()
            return
        }

        isSaving = true
        errorMessage = nil

        let sectionsSnapshot = draftSections
        let orderedLocationIds: [String?] = sectionsSnapshot.map { section in
            locationIdentifier(for: section)
        }
        do {
            try await viewModel.saveLocationOrder(with: orderedLocationIds)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func locationIdentifier(for section: RunLocationSection) -> String? {
        if let locationId = section.location?.id, !locationId.isEmpty {
            return locationId
        }
        if section.id == RunLocationSection.unassignedIdentifier || section.id.isEmpty {
            return nil
        }
        return section.id
    }
}

#Preview {
    

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
            .environment(\.colorScheme, .light)
    }
}
