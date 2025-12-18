import SwiftUI
import MapKit
import Contacts

struct CompanyLocationPickerView: View {
    @ObservedObject var viewModel: ProfileViewModel
    let company: CompanyInfo
    let showsCancel: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [AddressSearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false
    @State private var localErrorMessage: String?

    var body: some View {
        List {
            Section(header: Text("Selected Address")) {
                if viewModel.companyLocationAddress.isEmpty {
                    Text("No address saved")
                        .foregroundStyle(.secondary)
                } else {
                    Text(viewModel.companyLocationAddress)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Button(role: .destructive) {
                        saveAddress(nil)
                    } label: {
                        Label("Clear Address", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .disabled(viewModel.isUpdatingLocation)
                }
            }

            Section {
                TextField("Search for an address", text: $query)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .onSubmit {
                        Task {
                            await performSearch()
                        }
                    }
                    .onChange(of: query) { _, newValue in
                        scheduleSearch(for: newValue)
                    }

                ForEach(results) { result in
                    Button {
                        saveAddress(result.fullAddress)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(.label))

                            if let subtitle = result.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(Color(.secondaryLabel))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(viewModel.isUpdatingLocation)
                }

                if results.isEmpty, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSearching {
                    Text("No results yet. Keep typing to search.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let localErrorMessage {
                    Text(localErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Search Address")
            } footer: {
                if isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    EmptyView()
                }
            }
        }
        .navigationTitle("Company Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isUpdatingLocation)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isUpdatingLocation {
                    ProgressView()
                } else {
                    Button("Save") {
                        saveAddress(viewModel.companyLocationAddress)
                    }
                    .disabled(viewModel.companyLocationAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .keyboardDismissToolbar()
    }

    private func scheduleSearch(for text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 3 else {
            results = []
            isSearching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await performSearch()
        }
    }

    private func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return }

        await MainActor.run {
            isSearching = true
            localErrorMessage = nil
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = .address

        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            let mapped = response.mapItems.prefix(12).map(AddressSearchResult.init)
            await MainActor.run {
                results = mapped
                isSearching = false
            }
        } catch {
            await MainActor.run {
                isSearching = false
                results = []
                localErrorMessage = "Search failed. Please try again."
            }
        }
    }

    private func saveAddress(_ address: String?) {
        localErrorMessage = nil
        Task {
            let success = await viewModel.updateLocation(for: company.id, to: address)
            if success {
                dismiss()
            } else {
                await MainActor.run {
                    localErrorMessage = viewModel.errorMessage ?? "Unable to update location."
                }
            }
        }
    }
}

private struct AddressSearchResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let fullAddress: String

    init(mapItem: MKMapItem) {
        if #available(iOS 26, *) {
            let reps = mapItem.addressRepresentations
            let shortAddress = mapItem.address?.shortAddress
                ?? reps?.fullAddress(includingRegion: false, singleLine: true)
            let full = mapItem.address?.fullAddress
                ?? reps?.fullAddress(includingRegion: true, singleLine: true)

            let primaryName = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle = primaryName?.isEmpty == false ? primaryName! : (shortAddress ?? full ?? "Address")

            let subtitleCandidate = shortAddress ?? full
            if let subtitleCandidate, subtitleCandidate.caseInsensitiveCompare(displayTitle) != .orderedSame {
                subtitle = subtitleCandidate
            } else {
                subtitle = nil
            }

            title = displayTitle

            if let full, let primaryName, full.localizedCaseInsensitiveContains(primaryName) == false {
                fullAddress = "\(primaryName), \(full)"
            } else if let full {
                fullAddress = full
            } else if let subtitle {
                fullAddress = subtitle
            } else {
                fullAddress = displayTitle
            }
        } else {
            let formatter = CNPostalAddressFormatter()
            formatter.style = .mailingAddress

            if let postalAddress = mapItem.placemark.postalAddress {
                let formatted = formatter.string(from: postalAddress).replacingOccurrences(of: "\n", with: ", ")
                if let name = mapItem.name, !name.isEmpty, formatted.contains(name) == false {
                    title = name
                    subtitle = formatted
                    fullAddress = "\(name), \(formatted)"
                } else {
                    title = mapItem.name ?? formatted
                    subtitle = formatted == title ? nil : formatted
                    fullAddress = formatted
                }
            } else {
                let components = [
                    mapItem.name,
                    mapItem.placemark.thoroughfare,
                    mapItem.placemark.locality,
                    mapItem.placemark.administrativeArea,
                    mapItem.placemark.postalCode
                ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                let joined = components.joined(separator: ", ")
                title = mapItem.name ?? joined
                subtitle = joined == title ? nil : joined
                fullAddress = joined.isEmpty ? (mapItem.name ?? "Address") : joined
            }
        }
    }
}

#Preview {
    let viewModel = ProfileViewModel(
        authService: PreviewAuthService(),
        inviteCodesService: InviteCodesService()
    )
    viewModel.currentCompany = CompanyInfo(
        id: "company-123",
        name: "Preview Co",
        role: "OWNER",
        location: "123 Main St, Springfield",
        timeZone: "America/Chicago"
    )
    viewModel.companyLocationAddress = viewModel.currentCompany?.location ?? ""

    return NavigationStack {
        CompanyLocationPickerView(viewModel: viewModel, company: viewModel.currentCompany!, showsCancel: true)
    }
}
