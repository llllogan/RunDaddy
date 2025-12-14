import SwiftUI

struct SubstituteSkuSearchView: View {
    let pickItem: RunDetail.PickItem
    let runId: String
    let session: AuthSession
    let runsService: RunsServicing
    let onPickStatusChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [SearchResult] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedSkuResult: SearchResult?
    @State private var confirmingSubstitution = false
    @State private var errorMessage: String?

    private let searchService = SearchService()

    private var currentSkuLabel: String {
        let code = pickItem.sku?.code.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = pickItem.sku?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !code.isEmpty && !name.isEmpty {
            return "\(code) • \(name)"
        }
        return !code.isEmpty ? code : (!name.isEmpty ? name : "Unknown SKU")
    }

    private var isSubstituteEnabled: Bool {
        guard let selectedSkuResult else { return false }
        return selectedSkuResult.id != pickItem.sku?.id
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Current SKU") {
                    Text(currentSkuLabel)
                        .foregroundStyle(.secondary)
                }

                Section("Search Results") {
                    if isSearching {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Searching…")
                                .foregroundStyle(.secondary)
                        }
                    } else if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Search for a SKU to substitute.")
                            .foregroundStyle(.secondary)
                    } else if searchResults.isEmpty {
                        Text("No SKUs found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(searchResults) { result in
                            Button {
                                selectedSkuResult = result
                            } label: {
                                EntityResultRow(result: result, isSelected: selectedSkuResult?.id == result.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Substitute SKU")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Substitute") {
                        confirmingSubstitution = true
                    }
                    .disabled(!isSubstituteEnabled)
                }
            }
            .searchable(text: $searchText, prompt: "Search SKUs…")
            .onChange(of: searchText) { _, newValue in
                handleSearchTextChange(newValue)
            }
            .onSubmit(of: .search) {
                performSearch()
            }
            .onDisappear {
                searchDebounceTask?.cancel()
            }
            .alert("Are you sure?", isPresented: $confirmingSubstitution) {
                Button("Substitute", role: .destructive) {
                    Task {
                        await substituteSelectedSku()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will update this pick entry to use the selected SKU and keep the same count.")
            }
            .alert("Couldn't Substitute", isPresented: Binding(get: { errorMessage != nil }, set: { _, _ in errorMessage = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private func handleSearchTextChange(_ value: String) {
        searchDebounceTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            selectedSkuResult = nil
            return
        }

        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            performSearch()
        }
    }

    private func performSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task { @MainActor in
            isSearching = true
            defer { isSearching = false }

            do {
                let response = try await searchService.search(query: trimmed, results: [.sku])
                searchResults = response.results
                    .filter { $0.type == "sku" }
                if let selectedSkuResult, !searchResults.contains(where: { $0.id == selectedSkuResult.id }) {
                    self.selectedSkuResult = nil
                }
            } catch {
                searchResults = []
            }
        }
    }

    private func substituteSelectedSku() async {
        guard let selectedSkuResult else { return }

        do {
            try await runsService.substitutePickEntrySku(
                runId: runId,
                pickId: pickItem.id,
                skuId: selectedSkuResult.id,
                credentials: session.credentials
            )
            await onPickStatusChanged()
            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run {
                if let runError = error as? RunsServiceError {
                    errorMessage = runError.localizedDescription
                } else if let authError = error as? AuthError {
                    errorMessage = authError.localizedDescription
                } else {
                    errorMessage = "We couldn't substitute this pick entry right now. Please try again."
                }
            }
        }
    }
}
