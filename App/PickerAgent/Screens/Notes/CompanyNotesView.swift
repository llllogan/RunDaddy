import SwiftUI
import Combine

struct CompanyNotesView: View {
    @StateObject private var viewModel: CompanyNotesViewModel
    let onNotesUpdated: ((Int) -> Void)?
    @State private var showingComposer = false
    @State private var editingNote: Note? = nil

    init(session: AuthSession, notesService: NotesServicing? = nil, onNotesUpdated: ((Int) -> Void)? = nil) {
        _viewModel = StateObject(
            wrappedValue: CompanyNotesViewModel(
                session: session,
                notesService: notesService
            )
        )
        self.onNotesUpdated = onNotesUpdated
    }

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.notes.isEmpty {
                Section {
                    LoadingNotesRow(message: "Loading notes…")
                }
            } else if viewModel.notes.isEmpty {
                Section {
                    Text("No notes have been created today or yesterday.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            } else {
                ForEach(viewModel.groupedNotes, id: \.dateLabel) { group in
                    Section(group.dateLabel) {
                        ForEach(group.notes) { note in
                            NoteRowView(note: note)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if viewModel.canManageNotes {
                                        Button("Edit") {
                                            editingNote = note
                                            showingComposer = true
                                        }
                                        .tint(.blue)

                                        Button("Delete", role: .destructive) {
                                            Task {
                                                _ = await viewModel.delete(note: note)
                                                onNotesUpdated?(viewModel.total)
                                            }
                                        }
                                    }
                                }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingComposer = true
                } label: {
                    Label("Add Note", systemImage: "plus")
                }
            }
        }
        .refreshable {
            await viewModel.loadNotes(force: true)
        }
        .task {
            await viewModel.loadNotes()
            await viewModel.loadSuggestedTags()
        }
        .onChange(of: viewModel.total) { _, newValue in
            onNotesUpdated?(newValue)
        }
        .sheet(isPresented: $showingComposer) {
            CompanyNoteComposer(
                viewModel: viewModel,
                isPresented: $showingComposer,
                editingNote: editingNote,
                onNoteSaved: {
                    editingNote = nil
                    onNotesUpdated?(viewModel.total)
                }
            )
            .onDisappear {
                editingNote = nil
            }
        }
    }
}

@MainActor
final class CompanyNotesViewModel: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var total: Int = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isSearchingTags = false
    @Published private(set) var isDeleting = false
    @Published var errorMessage: String?
    @Published var tagSuggestions: [NoteTagOption] = []
    @Published var tagResults: [NoteTagOption] = []
    @Published private(set) var groupedNotes: [NoteDayGroup] = []

    let session: AuthSession
    private let notesService: NotesServicing
    private let searchService: SearchServicing

    init(session: AuthSession, notesService: NotesServicing? = nil, searchService: SearchServicing? = nil) {
        self.session = session
        self.notesService = notesService ?? NotesService()
        self.searchService = searchService ?? SearchService()
    }

    var canManageNotes: Bool {
        guard let rawRole = session.profile.role?.uppercased(),
              let role = UserRole(rawValue: rawRole) else {
            return false
        }
        return role == .admin || role == .owner || role == .god
    }

    func loadNotes(force: Bool = false) async {
        if isLoading && !force {
            return
        }

        isLoading = true

        do {
            let response = try await notesService.fetchNotes(
                runId: nil,
                includePersistentForRun: true,
                recentDays: 2,
                limit: 50,
                credentials: session.credentials
            )
            notes = response.notes
            total = response.total
            errorMessage = nil
            regroup()
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

    func addNote(body: String, tag: NoteTagOption) async -> Note? {
        if isSaving {
            return nil
        }

        isSaving = true
        defer { isSaving = false }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let request = CreateNoteRequest(
                body: trimmedBody,
                runId: nil,
                targetType: tag.type,
                targetId: tag.id
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
            let request = UpdateNoteRequest(
                body: trimmedBody,
                targetType: tag.type,
                targetId: tag.id
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
}

private struct CompanyNoteComposer: View {
    @ObservedObject var viewModel: CompanyNotesViewModel
    @Binding var isPresented: Bool
    let editingNote: Note?
    let onNoteSaved: () -> Void

    @State private var bodyText: String
    @State private var searchText = ""
    @State private var selectedTag: NoteTagOption?
    @State private var searchTask: Task<Void, Never>?

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
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedTag == nil || viewModel.isSaving
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Note") {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $bodyText)
                            .frame(minHeight: 120)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(.separator))
                            }

                        if bodyText.isEmpty {
                            Text("Add context or reminders for your team…")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 12)
                        }
                    }
                }

                Section("Apply to") {
                    TextField("Search SKUs, machines, or locations", text: $searchText)
                        .textFieldStyle(.roundedBorder)
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
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(option.label)
                                            .font(.headline)
                                            .foregroundStyle(.primary)

                                        if let subtitle = option.subtitle {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if selectedTag?.id == option.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
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
                            guard let tag = selectedTag else { return }
                            let note: Note?
                            if let editingNote {
                                note = await viewModel.update(note: editingNote, body: bodyText, tag: tag)
                            } else {
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
