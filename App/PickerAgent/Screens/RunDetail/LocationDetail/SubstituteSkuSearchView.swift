import SwiftUI

struct SubstituteSkuSearchView: View {
    let pickItem: RunDetail.PickItem
    let runId: String
    let session: AuthSession
    let runsService: RunsServicing
    let onPickStatusChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isQueryFocused: Bool

    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [SearchResult] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedSkuId: String?
    @State private var confirmingSubstitution = false
    @State private var showingNoteCreatedAlert = false
    @State private var errorMessage: String?

    private let searchService = SearchService()
    private let skusService = SkusService()
    private let notesService = NotesService()

    private var currentSkuLabel: String {
        let code = pickItem.sku?.code.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = pickItem.sku?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !code.isEmpty && !name.isEmpty {
            return "\(code) • \(name)"
        }
        return !code.isEmpty ? code : (!name.isEmpty ? name : "Unknown SKU")
    }

    private var isSubstituteEnabled: Bool {
        guard let selectedSkuId else { return false }
        return selectedSkuId != pickItem.sku?.id
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Current SKU") {
                    Text(currentSkuLabel)
                        .foregroundStyle(.secondary)
                }

                Section("Search") {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)

                        TextField("Search SKUs…", text: $searchText)
                            .focused($isQueryFocused)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit {
                                performSearch()
                            }

                        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear search")
                        }
                    }
                }

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Search Results") {
                        if isSearching {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Searching…")
                                    .foregroundStyle(.secondary)
                            }
                        } else if searchResults.isEmpty {
                            Text("No SKUs found.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(searchResults) { result in
                                Button {
                                    selectedSkuId = result.id
                                    isQueryFocused = false
                                } label: {
                                    EntityResultRow(result: result, isSelected: selectedSkuId == result.id)
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                            }
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
            .keyboardDismissToolbar()
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
                Text("This coil will be updated with the new SKU. The count will remain the same.")
            }
            .alert("Couldn't Substitute", isPresented: Binding(get: { errorMessage != nil }, set: { _, _ in errorMessage = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
            .alert("Substitution Complete", isPresented: $showingNoteCreatedAlert) {
                Button("OK", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("A note has been created for this run to document the substitution")
            }
        }
    }

    private func handleSearchTextChange(_ value: String) {
        searchDebounceTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
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
            } catch {
                searchResults = []
            }
        }
    }

    private func substituteSelectedSku() async {
        guard let selectedSkuId else { return }

        do {
            let newSku = try await skusService.getSku(id: selectedSkuId)
            try await runsService.substitutePickEntrySku(
                runId: runId,
                pickId: pickItem.id,
                skuId: selectedSkuId,
                credentials: session.credentials
            )
            let noteCreated = await createSubstitutionNoteIfPossible(newSku: newSku)
            await onPickStatusChanged()
            await MainActor.run {
                if noteCreated {
                    showingNoteCreatedAlert = true
                } else {
                    dismiss()
                }
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

    private func createSubstitutionNoteIfPossible(newSku: SKU) async -> Bool {
        guard let machineId = pickItem.machine?.id ?? pickItem.coilItem.coil.machineId else {
            return false
        }

        let oldName = pickItem.sku?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown SKU"
        let oldType = pickItem.sku?.type.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown Type"
        let newName = newSku.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newType = newSku.type.trimmingCharacters(in: .whitespacesAndNewlines)
        let coilCode = pickItem.coilItem.coil.code.trimmingCharacters(in: .whitespacesAndNewlines)
        let coilLabel = coilCode.isEmpty ? "Unknown Coil" : coilCode

        let body = "SKU substituted on coil \(coilLabel): Replaced \(oldName) (\(oldType)) with \(newName) (\(newType))."

        do {
            _ = try await notesService.createNote(
                request: CreateNoteRequest(body: body, runId: runId, targetType: .machine, targetId: machineId),
                credentials: session.credentials
            )
            return true
        } catch {
            // Notes are best-effort; ignore failures.
            return false
        }
    }
}
