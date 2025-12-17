import SwiftUI

struct SkuBulkActionView: View {
    enum Mode: Equatable {
        case bulkSetWeight
        case addToColdChest

        var title: String {
            switch self {
            case .bulkSetWeight:
                return "Bulk set SKU weight"
            case .addToColdChest:
                return "Add to Cold Chest"
            }
        }

        var actionTitle: String {
            switch self {
            case .bulkSetWeight:
                return "Update"
            case .addToColdChest:
                return "Add"
            }
        }
    }

    let mode: Mode
    let onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false
    @State private var suggestions: [SearchResult] = []
    @State private var results: [SearchResult] = []
    @State private var selected: [SearchResult] = []
    @State private var isSelectionExpanded = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    @State private var weightInputText = ""

    private let searchService: SearchServicing = SearchService()
    private let skusService: SkusServicing = SkusService()

    private var visibleSkus: [SearchResult] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? suggestions : results
    }

    private var selectedIds: [String] {
        selected.map(\.id)
    }

    private var selectedSummary: String {
        let titles = selected.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return titles.isEmpty ? "None" : titles.joined(separator: ", ")
    }

    private var parsedWeight: Double? {
        let trimmed = weightInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let normalizedText = trimmed.replacingOccurrences(of: ",", with: ".")
        let parsedNumber = SkuBulkActionView.weightFormatter.number(from: trimmed)?.doubleValue
            ?? Double(normalizedText)
        guard let parsedNumber, parsedNumber >= 0 else {
            return nil
        }
        return parsedNumber
    }

    private var isActionDisabled: Bool {
        if isSubmitting {
            return true
        }
        if selected.isEmpty {
            return true
        }
        if mode == .bulkSetWeight {
            return parsedWeight == nil
        }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                if mode == .bulkSetWeight {
                    Section("Weight") {
                        TextField("Weight (g)", text: $weightInputText)
                            .keyboardType(.decimalPad)

                        if weightInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Enter the weight you want to apply to the selected SKUs.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if parsedWeight == nil {
                            Text("Enter a valid non-negative weight.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Selection") {
                    Text(selectedSummary)
                        .foregroundStyle(selected.isEmpty ? .secondary : .primary)

                    Button(isSelectionExpanded ? "Collapse" : "Expand") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSelectionExpanded.toggle()
                        }
                    }
                    .disabled(selected.isEmpty)

                    if isSelectionExpanded {
                        ForEach(selected) { sku in
                            HStack(spacing: 12) {
                                EntityResultRow(result: sku, showsSubheadline: true, iconDiameter: 30, iconFontSize: 14)
                                Button {
                                    removeFromSelection(sku)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(sku.title) from selection")
                            }
                        }
                    }
                }

                Section("Search") {
                    TextField("Search SKUs", text: $searchText)
                        .onChange(of: searchText) { _, newValue in
                            handleSearchTextChanged(newValue)
                        }

                    if isSearching {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Searching…")
                                .foregroundStyle(.secondary)
                        }
                    } else if visibleSkus.isEmpty {
                        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Start typing to find SKUs. Recent suggestions will appear here.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            Text("No SKUs match your search yet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        }
                    } else {
                        ForEach(visibleSkus) { sku in
                            Button {
                                toggleSelection(sku)
                            } label: {
                                EntityResultRow(result: sku, isSelected: isSelected(sku))
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.actionTitle) {
                        Task { await submit() }
                    }
                    .disabled(isActionDisabled)
                }
            }
            .task {
                await loadSuggestions()
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    private func handleSearchTextChanged(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do {
                let response = try await searchService.search(query: trimmed, results: [.sku])
                await MainActor.run {
                    results = response.results.filter { $0.type.lowercased() == "sku" }
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    results = []
                    isSearching = false
                }
            }
        }
    }

    private func loadSuggestions() async {
        do {
            let response = try await searchService.fetchSuggestions(lookbackDays: 14)
            await MainActor.run {
                suggestions = response.results.filter { $0.type.lowercased() == "sku" }
            }
        } catch {
            await MainActor.run {
                suggestions = []
            }
        }
    }

    private func isSelected(_ sku: SearchResult) -> Bool {
        selected.contains(where: { $0.id == sku.id })
    }

    private func toggleSelection(_ sku: SearchResult) {
        if let index = selected.firstIndex(where: { $0.id == sku.id }) {
            selected.remove(at: index)
        } else {
            selected.append(sku)
        }
    }

    private func removeFromSelection(_ sku: SearchResult) {
        selected.removeAll(where: { $0.id == sku.id })
    }

    @MainActor
    private func submit() async {
        errorMessage = nil

        guard !selected.isEmpty else {
            errorMessage = "Select at least one SKU."
            return
        }

        if mode == .bulkSetWeight, parsedWeight == nil {
            errorMessage = "Enter a valid non-negative weight."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            switch mode {
            case .bulkSetWeight:
                guard let weight = parsedWeight else { return }
                _ = try await skusService.bulkUpdateWeight(skuIds: selectedIds, weight: weight)
            case .addToColdChest:
                _ = try await skusService.bulkAddToColdChest(skuIds: selectedIds)
            }
            onComplete?()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static let weightFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter
    }()
}

