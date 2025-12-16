import SwiftUI
import Combine

private enum NoteComposerIntent: Identifiable {
    case add
    case edit(Note)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let note):
            return "edit-\(note.id)"
        }
    }

    var note: Note? {
        switch self {
        case .add:
            return nil
        case .edit(let note):
            return note
        }
    }
}

struct CompanyNotesView: View {
    @StateObject private var viewModel: CompanyNotesViewModel
    let onNotesUpdated: ((Int) -> Void)?
    @State private var composerIntent: NoteComposerIntent?
    let session: AuthSession
    @State private var activeFilterTag: NoteTagOption?
    @State private var isShowingFilterPicker = false
    @State private var filterPickerType: NoteTargetType = .sku

    init(
        session: AuthSession,
        notesService: NotesServicing? = nil,
        searchService: SearchServicing? = nil,
        runsService: RunsServicing? = nil,
        initialFilterTag: NoteTagOption? = nil,
        onNotesUpdated: ((Int) -> Void)? = nil
    ) {
        self.session = session
        self._activeFilterTag = State(initialValue: initialFilterTag)
        _viewModel = StateObject(
            wrappedValue: CompanyNotesViewModel(
                session: session,
                notesService: notesService,
                searchService: searchService,
                runsService: runsService
            )
        )
        self.onNotesUpdated = onNotesUpdated
    }

    var body: some View {
        List {
            Section {
                NotesFilterBar(
                    selectedTag: activeFilterTag,
                    onSelectAll: {
                        activeFilterTag = nil
                        Task { await viewModel.loadNotes(force: true, filterTag: nil) }
                    },
                    onSelectType: { type in
                        filterPickerType = type
                        isShowingFilterPicker = true
                    }
                )
            }

            if viewModel.isLoading && viewModel.notes.isEmpty {
                Section {
                    LoadingNotesRow(message: "Loading notes…")
                }
            } else if viewModel.notes.isEmpty {
                Section {
                    Text(activeFilterTag == nil ? "No notes have been created yet." : "No notes found for this item.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            } else {
                ForEach(viewModel.groupedNotes, id: \.dateLabel) { group in
                    CompanyNotesSection(
                        group: group,
                        runDates: viewModel.runDates,
                        onEdit: { note in composerIntent = .edit(note) },
                        onDelete: { note in handleDelete(note) }
                    )
                }

                if viewModel.hasMoreNotes {
                    Section {
                        Button {
                            Task { await viewModel.loadMoreNotes(filterTag: activeFilterTag) }
                        } label: {
                            if viewModel.isLoadingMore {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Loading more…")
                                }
                            } else {
                                Text("Load more")
                            }
                        }
                        .disabled(viewModel.isLoadingMore)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    composerIntent = .add
                } label: {
                    Label("Add Note", systemImage: "plus")
                }
            }
        }
        .refreshable {
            await viewModel.loadNotes(force: true, filterTag: activeFilterTag)
        }
        .task {
            await viewModel.loadNotes(filterTag: activeFilterTag)
            await viewModel.loadSuggestedTags()
        }
        .onChange(of: session.credentials.accessToken) {
            viewModel.resetSession(session)
            Task {
                await viewModel.loadNotes(force: true, filterTag: activeFilterTag)
                await viewModel.loadSuggestedTags()
            }
        }
        .onChange(of: viewModel.total) { _, newValue in
            onNotesUpdated?(newValue)
        }
        .sheet(item: $composerIntent) { intent in
            CompanyNoteComposer(
                viewModel: viewModel,
                isPresented: Binding(
                    get: { composerIntent != nil },
                    set: { isPresented in
                        if !isPresented {
                            composerIntent = nil
                        }
                    }
                ),
                editingNote: intent.note,
                onNoteSaved: {
                    composerIntent = nil
                    onNotesUpdated?(viewModel.total)
                }
            )
        }
        .sheet(isPresented: $isShowingFilterPicker) {
            NotesTargetFilterPickerSheet(
                session: session,
                targetType: filterPickerType,
                selectedTag: $activeFilterTag,
                onSelected: { tag in
                    activeFilterTag = tag
                    Task { await viewModel.loadNotes(force: true, filterTag: tag) }
                }
            )
        }
    }

    private func handleDelete(_ note: Note) {
        Task {
            _ = await viewModel.delete(note: note)
            onNotesUpdated?(viewModel.total)
        }
    }
}

private struct CompanyNotesSection: View {
    let group: NoteDayGroup
    let runDates: [String: Date]
    let onEdit: (Note) -> Void
    let onDelete: (Note) -> Void

    var body: some View {
        Section(group.dateLabel) {
            ForEach(group.notes) { note in
                NoteRowView(note: note, runDate: runDate(for: note))
                    .contentShape(Rectangle())
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { onEdit(note) } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)

                        Button(role: .destructive) { onDelete(note) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func runDate(for note: Note) -> Date? {
        guard let runId = note.runId else { return nil }
        return runDates[runId]
    }
}

@MainActor
final class CompanyNotesViewModel: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var total: Int = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isSaving = false
    @Published private(set) var isSearchingTags = false
    @Published private(set) var isDeleting = false
    @Published var errorMessage: String?
    @Published var tagSuggestions: [NoteTagOption] = []
    @Published var tagResults: [NoteTagOption] = []
    @Published private(set) var groupedNotes: [NoteDayGroup] = []
    @Published private(set) var runDates: [String: Date] = [:]

    private var session: AuthSession
    private let notesService: NotesServicing
    private let searchService: SearchServicing
    private let runsService: RunsServicing
    private var failedRunIds = Set<String>()
    private let pageSize = 100

    init(
        session: AuthSession,
        notesService: NotesServicing? = nil,
        searchService: SearchServicing? = nil,
        runsService: RunsServicing? = nil
    ) {
        self.session = session
        self.notesService = notesService ?? NotesService()
        self.searchService = searchService ?? SearchService()
        self.runsService = runsService ?? RunsService()
    }

    func resetSession(_ session: AuthSession) {
        self.session = session
        notes = []
        total = 0
        groupedNotes = []
        runDates = [:]
        errorMessage = nil
        isLoading = false
        isLoadingMore = false
    }

    var hasMoreNotes: Bool {
        notes.count < total
    }

    func loadNotes(force: Bool = false, filterTag: NoteTagOption? = nil) async {
        if isLoading && !force {
            return
        }

        if force {
            failedRunIds.removeAll()
        }

        isLoading = true
        if force {
            notes = []
            total = 0
            groupedNotes = []
            runDates = [:]
        }

        do {
            let response = try await fetchNotesPage(offset: 0, filterTag: filterTag)
            notes = response.notes
            total = response.total
            errorMessage = nil
            regroup()
            await loadRunDates(for: response.notes)
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let notesError = error as? NotesServiceError {
                errorMessage = notesError.localizedDescription
            } else {
                errorMessage = "We couldn't load notes right now. Please pull to refresh."
            }
        }

        isLoading = false
    }

    func loadMoreNotes(filterTag: NoteTagOption? = nil) async {
        if isLoadingMore || isLoading || !hasMoreNotes {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let response = try await fetchNotesPage(offset: notes.count, filterTag: filterTag)
            if !response.notes.isEmpty {
                notes.append(contentsOf: response.notes)
            }
            total = response.total
            errorMessage = nil
            regroup()
            await loadRunDates(for: response.notes)
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let notesError = error as? NotesServiceError {
                errorMessage = notesError.localizedDescription
            } else {
                errorMessage = "We couldn't load more notes right now. Please try again."
            }
        }
    }

    func addNote(body: String, tag: NoteTagOption) async -> Note? {
        if isSaving {
            return nil
        }

        isSaving = true
        defer { isSaving = false }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let isGeneral = tag.type == .general
            let request = CreateNoteRequest(
                body: trimmedBody,
                runId: nil,
                targetType: tag.type,
                targetId: isGeneral ? nil : tag.id
            )
            let note = try await notesService.createNote(request: request, credentials: session.credentials)
            notes.insert(note, at: 0)
            total += 1
            errorMessage = nil
            regroup()
            return note
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let notesError = error as? NotesServiceError {
                errorMessage = notesError.localizedDescription
            } else {
                errorMessage = "We couldn't save this note. Please try again."
            }
            return nil
        }
    }

    func update(note: Note, body: String, tag: NoteTagOption) async -> Note? {
        if isSaving {
            return nil
        }

        isSaving = true
        defer { isSaving = false }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let isGeneral = tag.type == .general
            let request = UpdateNoteRequest(
                body: trimmedBody,
                targetType: tag.type,
                targetId: isGeneral ? nil : tag.id
            )
            let updated = try await notesService.updateNote(noteId: note.id, request: request, credentials: session.credentials)
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = updated
            }
            regroup()
            errorMessage = nil
            return updated
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let notesError = error as? NotesServiceError {
                errorMessage = notesError.localizedDescription
            } else {
                errorMessage = "We couldn't save this note. Please try again."
            }
            return nil
        }
    }

    func delete(note: Note) async -> Bool {
        if isDeleting {
            return false
        }

        isDeleting = true
        defer { isDeleting = false }

        do {
            try await notesService.deleteNote(noteId: note.id, credentials: session.credentials)
            notes.removeAll { $0.id == note.id }
            total = max(total - 1, 0)
            regroup()
            return true
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let notesError = error as? NotesServiceError {
                errorMessage = notesError.localizedDescription
            } else {
                errorMessage = "We couldn't delete this note. Please try again."
            }
            return false
        }
    }

    func loadSuggestedTags() async {
        do {
            let suggestions = try await searchService.fetchSuggestions(lookbackDays: 7)
            tagSuggestions = suggestions.results.compactMap { result in
                guard let type = NoteTargetType(rawValue: result.type) else { return nil }
                return NoteTagOption(id: result.id, type: type, label: result.title, subtitle: result.subtitle)
            }
        } catch {
            // Suggestions are optional; we can ignore failures silently.
        }
    }

    func searchTags(matching query: String) async {
        if isSearchingTags {
            return
        }

        isSearchingTags = true
        defer { isSearchingTags = false }

        do {
            let response = try await searchService.search(query: query)
            tagResults = response.results.compactMap { result in
                guard let type = NoteTargetType(rawValue: result.type) else { return nil }
                return NoteTagOption(id: result.id, type: type, label: result.title, subtitle: result.subtitle)
            }
        } catch {
            // Keep existing tagResults; errors will be surfaced by the composer if needed.
        }
    }

    func clearSearchResults() {
        tagResults = []
    }

    private func fetchNotesPage(offset: Int, filterTag: NoteTagOption?) async throws -> NotesResponse {
        if let filterTag {
            return try await notesService.fetchNotes(
                targetType: filterTag.type,
                targetId: filterTag.id,
                limit: pageSize,
                offset: offset,
                credentials: session.credentials
            )
        }

        return try await notesService.fetchNotes(
            runId: nil,
            includePersistentForRun: true,
            recentDays: nil,
            limit: pageSize,
            offset: offset,
            credentials: session.credentials
        )
    }

    private func regroup() {
        let grouped = Dictionary(grouping: notes) { note in
            note.createdAt.formatted(date: .abbreviated, time: .omitted)
        }

        groupedNotes = grouped
            .map { key, value in
                NoteDayGroup(dateLabel: key, notes: value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { lhs, rhs in
                guard let lhsDate = lhs.notes.first?.createdAt, let rhsDate = rhs.notes.first?.createdAt else {
                    return lhs.dateLabel > rhs.dateLabel
                }
                return lhsDate > rhsDate
            }
    }

    private func loadRunDates(for notes: [Note]) async {
        let uniqueRunIds = Set(notes.compactMap { $0.runId })
        let pendingRunIds = uniqueRunIds.filter { runId in
            runDates[runId] == nil && !failedRunIds.contains(runId)
        }

        guard !pendingRunIds.isEmpty else { return }

        for runId in pendingRunIds {
            do {
                let detail = try await runsService.fetchRunDetail(withId: runId, credentials: session.credentials)
                runDates[runId] = detail.runDate
            } catch {
                failedRunIds.insert(runId)
            }
        }
    }
}

private struct NotesFilterBar: View {
    let selectedTag: NoteTagOption?
    let onSelectAll: () -> Void
    let onSelectType: (NoteTargetType) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    onSelectAll()
                } label: {
                    Text(selectedTag == nil ? "All" : "Clear")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onSelectType(.sku)
                } label: {
                    filterChip(label: selectedTagLabel(for: .sku))
                }
                .buttonStyle(.plain)

                Button {
                    onSelectType(.machine)
                } label: {
                    filterChip(label: selectedTagLabel(for: .machine))
                }
                .buttonStyle(.plain)

                Button {
                    onSelectType(.location)
                } label: {
                    filterChip(label: selectedTagLabel(for: .location))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
    }

    private func selectedTagLabel(for type: NoteTargetType) -> String {
        guard let selectedTag, selectedTag.type == type else {
            switch type {
            case .sku: return "SKU"
            case .machine: return "Machine"
            case .location: return "Location"
            case .general: return "General"
            }
        }
        return selectedTag.label
    }
}

private struct NotesTargetFilterPickerSheet: View {
    let session: AuthSession
    let targetType: NoteTargetType
    @Binding var selectedTag: NoteTagOption?
    let onSelected: (NoteTagOption) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [SearchResult] = []
    @State private var searchDebounceTask: Task<Void, Never>?

    private let searchService = SearchService()

    private var searchFilters: [SearchResultFilter] {
        switch targetType {
        case .sku: return [.sku]
        case .machine: return [.machine]
        case .location: return [.location]
        case .general: return []
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Search") {
                    TextField("Search…", text: $searchText)
                        .onChange(of: searchText) { _, newValue in
                            handleSearchTextChange(newValue)
                        }
                }

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Results") {
                        if isSearching {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Searching…")
                                    .foregroundStyle(.secondary)
                            }
                        } else if searchResults.isEmpty {
                            Text("No results found.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(searchResults) { result in
                                Button {
                                    let type = NoteTargetType(rawValue: result.type) ?? targetType
                                    let tag = NoteTagOption(
                                        id: result.id,
                                        type: type,
                                        label: result.title,
                                        subtitle: result.subtitle
                                    )
                                    selectedTag = tag
                                    onSelected(tag)
                                    dismiss()
                                } label: {
                                    EntityResultRow(result: result, isSelected: selectedTag?.id == result.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Filter \(targetType.rawValue.uppercased()) Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onDisappear {
                searchDebounceTask?.cancel()
            }
        }
    }

    private func handleSearchTextChange(_ value: String) {
        searchDebounceTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(trimmed)
        }
    }

    private func performSearch(_ query: String) async {
        isSearching = true
        defer { isSearching = false }

        do {
            let response = try await searchService.search(query: query, results: searchFilters)
            searchResults = response.results.filter { $0.type == targetType.rawValue }
        } catch {
            searchResults = []
        }
    }
}

private struct CompanyNoteComposer: View {
    @ObservedObject var viewModel: CompanyNotesViewModel
    @Binding var isPresented: Bool
    let editingNote: Note?
    let onNoteSaved: () -> Void

    @FocusState private var isBodyFocused: Bool
    @State private var bodyText: String
    @State private var searchText = ""
    @State private var selectedTag: NoteTagOption?
    @State private var searchTask: Task<Void, Never>?
    @State private var isShowingGeneralConfirm = false

    init(
        viewModel: CompanyNotesViewModel,
        isPresented: Binding<Bool>,
        editingNote: Note?,
        onNoteSaved: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self._isPresented = isPresented
        self.editingNote = editingNote
        self.onNoteSaved = onNoteSaved
        _bodyText = State(initialValue: editingNote?.body ?? "")
        if let editingNote {
            let initialTag = NoteTagOption(
                id: editingNote.target.id,
                type: editingNote.target.type,
                label: editingNote.target.label,
                subtitle: editingNote.target.subtitle
            )
            _selectedTag = State(initialValue: initialTag)
        } else {
            _selectedTag = State(initialValue: nil)
        }
    }

    private var visibleTags: [NoteTagOption] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return viewModel.tagSuggestions
        }
        return viewModel.tagResults
    }

    private var isSaveDisabled: Bool {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSaving
    }

    var body: some View {
        let isEditing = editingNote != nil

        NavigationStack {
            List {
                Section("Note") {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $bodyText)
                            .frame(minHeight: 120)
                            .focused($isBodyFocused)

                        if bodyText.isEmpty {
                            Text("Add context or reminders for your team…")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 10)
                        }
                    }
                }

                if !isEditing {
                    Section("Apply to") {
                        TextField("Search SKUs, machines, or locations", text: $searchText)
                            .onChange(of: searchText) { _, newValue in
                                searchTask?.cancel()
                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard trimmed.count >= 2 else {
                                    viewModel.clearSearchResults()
                                    return
                                }

                                searchTask = Task {
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    await viewModel.searchTags(matching: trimmed)
                                }
                            }

                        if visibleTags.isEmpty {
                            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Start typing to find SKUs, machines, or locations. Recent suggestions will appear here.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 4)
                            } else {
                                Text("No tags match your search yet.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 4)
                            }
                        } else {
                            ForEach(visibleTags) { option in
                                Button {
                                    selectedTag = option
                                } label: {
                                    EntityResultRow(option: option, isSelected: selectedTag?.id == option.id)
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(editingNote == nil ? "Add Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let note: Note?
                            if let editingNote {
                                guard let tag = selectedTag else { return }
                                note = await viewModel.update(note: editingNote, body: bodyText, tag: tag)
                            } else {
                                guard let tag = selectedTag else {
                                    isShowingGeneralConfirm = true
                                    return
                                }
                                note = await viewModel.addNote(body: bodyText, tag: tag)
                            }
                            if note != nil {
                                onNoteSaved()
                                isPresented = false
                                bodyText = ""
                                searchText = ""
                                selectedTag = nil
                            }
                        }
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
        .alert("No tag selected", isPresented: $isShowingGeneralConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Yes") {
                Task {
                    let tag = NoteTagOption(id: "general", type: .general, label: "General", subtitle: nil)
                    let note = await viewModel.addNote(body: bodyText, tag: tag)
                    if note != nil {
                        onNoteSaved()
                        isPresented = false
                        bodyText = ""
                        searchText = ""
                        selectedTag = nil
                    }
                }
            }
        } message: {
            Text("Are you sure you dont want to tag this note with a SKU, machine, or location?")
        }
        .task {
            guard !isEditing else { return }
            await MainActor.run {
                isBodyFocused = true
            }
        }
    }
}

private struct LoadingNotesRow: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
