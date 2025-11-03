//
//  LocationDetailView.swift
//  RunDaddy
//
//  Created by opencode on 2025-11-03.
//

import SwiftUI

struct LocationDetailView: View {
    let locationId: String

    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsKeys.navigationApp) private var navigationAppRawValue: String = NavigationApp.appleMaps.rawValue
    @State private var location: APILocation?
    @State private var machines: [APIMachine] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let locationsService = LocationsService()
    private let machinesService = MachinesService()

    private var navigationApp: NavigationApp {
        NavigationApp(rawValue: navigationAppRawValue) ?? .appleMaps
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading location details...")
            } else if let error = errorMessage {
                ContentUnavailableView("Error loading location",
                                      systemImage: "exclamationmark.triangle",
                                      description: Text(error))
            } else if let location = location {
                List {
                    Section("Location Information") {
                        LabeledContent("Name", value: location.name)
                        if let address = location.address {
                            LabeledContent("Address", value: address)
                        }
                    }

                    Section("Machines") {
                        if machines.isEmpty {
                            Text("No machines found at this location.")
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
                                        Text(machine.machineType.name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle(location.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            openDirections(to: location)
                        } label: {
                            Label("Directions", systemImage: "map")
                        }
                        .disabled(mapsURL(for: location) == nil)
                    }
                }
            } else {
                ContentUnavailableView("Location not found",
                                      systemImage: "mappin",
                                      description: Text("The requested location could not be loaded."))
            }
        }
        .task {
            await fetchData()
        }
    }

    private func fetchData() async {
        isLoading = true
        errorMessage = nil
        do {
            async let locationTask = locationsService.fetchLocation(id: locationId)
            async let machinesTask = machinesService.fetchMachines()

            let (fetchedLocation, allMachines) = try await (locationTask, machinesTask)

            location = fetchedLocation
            machines = allMachines.filter { $0.locationId == locationId }
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