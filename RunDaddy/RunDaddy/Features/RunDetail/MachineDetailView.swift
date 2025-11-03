//
//  MachineDetailView.swift
//  RunDaddy
//
//  Created by opencode on 2025-11-03.
//

import SwiftUI

struct MachineDetailView: View {
    let machineId: String

    @State private var machine: APIMachine?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let machinesService = MachinesService()

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading machine details...")
            } else if let error = errorMessage {
                ContentUnavailableView("Error loading machine",
                                      systemImage: "exclamationmark.triangle",
                                      description: Text(error))
            } else if let machine = machine {
                List {
                    Section("Machine Information") {
                        LabeledContent("Code", value: machine.code)
                        if let description = machine.description {
                            LabeledContent("Description", value: description)
                        }
                        LabeledContent("Type", value: machine.machineType.name)
                        if let typeDescription = machine.machineType.description {
                            LabeledContent("Type Description", value: typeDescription)
                        }
                    }

                    if let location = machine.location {
                        Section("Location") {
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
                .navigationTitle(machine.code)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Machine not found",
                                      systemImage: "building.2",
                                      description: Text("The requested machine could not be loaded."))
            }
        }
        .task {
            do {
                try await fetchMachine()
            } catch let error {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func fetchMachine() async throws {
        isLoading = true
        errorMessage = nil
        machine = try await machinesService.fetchMachine(id: machineId)
        isLoading = false
    }
}