import SwiftUI

struct MachineDetailView: View {
    let machineId: String
    let session: AuthSession
    
    @State private var machine: Machine?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading machine details...")
            } else if let errorMessage = errorMessage {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if let machine = machine {
                List {
                    Section("Machine Information") {
                        HStack {
                            Text("Code")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(machine.code)
                                .foregroundColor(.primary)
                        }
                        if let description = machine.description {
                            HStack {
                                Text("Description")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(description)
                                    .foregroundColor(.primary)
                            }
                        }
                        if let location = machine.location {
                            HStack {
                                Text("Location")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(location.name)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
                .navigationTitle(machine.code)
                .navigationBarTitleDisplayMode(.large)
            }
        }
        .task {
            await loadMachineDetails()
        }
    }
    
    private func loadMachineDetails() async {
        do {
            machine = try await MachinesService().getMachine(id: machineId)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}