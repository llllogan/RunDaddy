import SwiftUI

struct SearchLocationDetailView: View {
    let locationId: String
    let session: AuthSession
    
    @State private var location: Location?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading location details...")
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
            } else if let location = location {
                List {
                    Section("Location Information") {
                        HStack {
                            Text("Name")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(location.name)
                                .foregroundColor(.primary)
                        }
                        if let address = location.address {
                            HStack {
                                Text("Address")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(address)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
                .navigationTitle(location.name)
                .navigationBarTitleDisplayMode(.large)
            }
        }
        .task {
            await loadLocationDetails()
        }
    }
    
    private func loadLocationDetails() async {
        do {
            location = try await LocationsService().getLocation(id: locationId)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}