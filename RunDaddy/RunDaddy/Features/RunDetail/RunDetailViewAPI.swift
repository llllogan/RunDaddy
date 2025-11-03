//
//  RunDetailViewAPI.swift
//  RunDaddy
//
//  Created by opencode on 2025-11-03.
//

import SwiftUI

struct RunDetailAPIView: View {
    let runId: String

    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsKeys.navigationApp) private var navigationAppRawValue: String = NavigationApp.appleMaps.rawValue
    @State private var run: APIDetailedRun?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let runsDetailService = RunsDetailService()

    private var navigationApp: NavigationApp {
        NavigationApp(rawValue: navigationAppRawValue) ?? .appleMaps
    }

    private var locations: [APILocation] {
        guard let run = run else { return [] }
        let locationIds = Set(run.pickEntries.compactMap { $0.coilItem.coil.machine.location?.id })
        return run.pickEntries.compactMap { $0.coilItem.coil.machine.location }.filter { locationIds.contains($0.id) }
    }

    private var machines: [APIMachine] {
        guard let run = run else { return [] }
        let machineIds = Set(run.pickEntries.map { $0.coilItem.coil.machine.id })
        return run.pickEntries.map { $0.coilItem.coil.machine }.filter { machineIds.contains($0.id) }
    }

    private var totalCoils: Int {
        run?.pickEntries.count ?? 0
    }

    private var packedCount: Int {
        run?.pickEntries.filter { $0.status == "PICKED" }.count ?? 0
    }

    private var navigationTitle: String {
        run?.scheduledFor?.formatted(.dateTime.day().month().year()) ?? "Run Details"
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading run details...")
            } else if let error = errorMessage {
                ContentUnavailableView("Error loading run",
                                      systemImage: "exclamationmark.triangle",
                                      description: Text(error))
            } else if let run = run {
                List {
                    Section("Run Information") {
                        LabeledContent("Status", value: run.status.capitalized)
                        if let scheduled = run.scheduledFor {
                            LabeledContent("Scheduled", value: scheduled.formatted(.dateTime.day().month().year()))
                        }
                        if let started = run.pickingStartedAt {
                            LabeledContent("Started", value: started.formatted(.dateTime.day().month().year()))
                        }
                        if let ended = run.pickingEndedAt {
                            LabeledContent("Ended", value: ended.formatted(.dateTime.day().month().year()))
                        }
                        if let pickerName = run.pickerFullName {
                            LabeledContent("Picker", value: pickerName)
                        }
                        if let runnerName = run.runnerFullName {
                            LabeledContent("Runner", value: runnerName)
                        }
                        LabeledContent("Total Items", value: "\(totalCoils)")
                        LabeledContent("Packed Items", value: "\(packedCount)")
                    }

                    Section("Locations") {
                        if locations.isEmpty {
                            Text("No locations found for this run.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(locations) { location in
                                NavigationLink {
                                    LocationDetailView(locationId: location.id)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(location.name)
                                        if let address = location.address {
                                            Text(address)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Section("Machines") {
                        if machines.isEmpty {
                            Text("No machines found for this run.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(machines) { machine in
                                NavigationLink {
                                    MachineDetailView(machineId: machine.id)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(machine.code)
                                        if let description = machine.description {
                                            Text(description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let locationName = machine.location?.name {
                                            Text("📍 \(locationName)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            ForEach(locations) { location in
                                Button {
                                    openDirections(to: location)
                                } label: {
                                    Label(location.name, systemImage: "mappin.and.ellipse")
                                }
                                .disabled(mapsURL(for: location) == nil)
                            }
                        } label: {
                            Label("Directions", systemImage: "map")
                        }
                        .disabled(locations.isEmpty)
                    }
                }
            } else {
                ContentUnavailableView("Run not found",
                                      systemImage: "tray",
                                      description: Text("The requested run could not be loaded."))
            }
        }
        .task {
            await fetchRun()
        }
    }

    private func fetchRun() async {
        isLoading = true
        errorMessage = nil
        do {
            run = try await runsDetailService.fetchRun(id: runId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func openDirections(to location: APILocation) {
        guard let url = mapsURL(for: location) else { return }
        openURL(url)
    }

    private func mapsURL(for location: APILocation) -> URL? {
        let trimmedAddress = location.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedAddress.isEmpty else { return nil }

        guard let encodedAddress = trimmedAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        switch navigationApp {
        case .appleMaps:
            return URL(string: "http://maps.apple.com/?q=\(encodedAddress)")
        case .waze:
            return URL(string: "https://www.waze.com/ul?q=\(encodedAddress)&navigate=yes")
        }
    }
}