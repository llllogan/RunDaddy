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

struct RunNotesView: View {
    @StateObject private var viewModel: RunNotesViewModel
    let onNotesUpdated: ((Int) -> Void)?
    @State private var composerIntent: NoteComposerIntent?

    init(
        runId: String,
        session: AuthSession,
        runDetail: RunDetail?,
        notesService: NotesServicing? = nil,
        onNotesUpdated: ((Int) -> Void)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: RunNotesViewModel(
                runId: runId,
                session: session,
                runDetail: runDetail,
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
                    Text("No notes have been added to this run yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            } else {
                ForEach(viewModel.groupedNotes, id: \.dateLabel) { group in
                    Section(group.dateLabel) {
                        ForEach(group.notes) { note in
                            NoteRowView(note: note)
                                .contentShape(Rectangle())
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        composerIntent = .edit(note)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)

                                    Button(role: .destructive) {
                                        Task {
                                            _ = await viewModel.delete(note: note)
                                            onNotesUpdated?(viewModel.total)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
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
                    composerIntent = .add
                } label: {
                    Label("Add Note", systemImage: "plus")
                }
                .disabled(viewModel.tagOptions.isEmpty)
            }
        }
        .refreshable {
            await viewModel.loadNotes(force: true)
        }
        .task {
            await viewModel.loadNotes()
        }
        .onChange(of: viewModel.total) { _, newValue in
            onNotesUpdated?(newValue)
        }
        .sheet(item: $composerIntent) { intent in
            RunNoteComposer(
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
    }
}

@MainActor
final class RunNotesViewModel: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var total: Int = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published private(set) var isDeleting = false

    let runId: String
    let tagOptions: [NoteTagOption]

    let session: AuthSession
    private let notesService: NotesServicing

    init(
        runId: String,
        session: AuthSession,
        runDetail: RunDetail?,
        notesService: NotesServicing? = nil
    ) {
        self.runId = runId
        self.session = session
        self.notesService = notesService ?? NotesService()
        self.tagOptions = RunNotesViewModel.buildTagOptions(from: runDetail)
    }

    func loadNotes(force: Bool = false) async {
        if isLoading && !force {
            return
        }

        isLoading = true

        do {
            let response = try await notesService.fetchNotes(
                runId: runId,
                includePersistentForRun: true,
                recentDays: nil,
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
                errorMessage = "We couldn't load notes for this run. Please pull to refresh."
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
                runId: runId,
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

    var groupedNotes: [NoteDayGroup] = []

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

    private static func buildTagOptions(from detail: RunDetail?) -> [NoteTagOption] {
        guard let detail else { return [] }

        var options: [NoteTagOption] = []
        var seen = Set<String>()

        // SKUs from pick items
        for item in detail.pickItems {
            guard let sku = item.sku, !seen.contains(sku.id) else { continue }
            seen.insert(sku.id)
            let subtitleParts = [
                sku.name.trimmingCharacters(in: .whitespacesAndNewlines),
                Self.normalizedSkuType(sku.type)
            ].compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            let subtitle = subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " • ")
            options.append(
                NoteTagOption(
                    id: sku.id,
                    type: .sku,
                    label: sku.code,
                    subtitle: subtitle
                )
            )
        }

        // Machines
        for machine in detail.machines {
            guard !seen.contains(machine.id) else { continue }
            seen.insert(machine.id)
            let subtitleParts = [
                machine.description?.trimmingCharacters(in: .whitespacesAndNewlines),
            ].compactMap { part -> String? in
                if let part, !part.isEmpty {
                    return part
                }
                return nil
            }

            options.append(
                NoteTagOption(
                    id: machine.id,
                    type: .machine,
                    label: machine.code,
                    subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " • ")
                )
            )
        }

        // Locations
        for location in detail.locations {
            guard !seen.contains(location.id) else { continue }
            seen.insert(location.id)
            let title = location.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = location.address?.trimmingCharacters(in: .whitespacesAndNewlines)

            options.append(
                NoteTagOption(
                    id: location.id,
                    type: .location,
                    label: (title?.isEmpty == false ? title : nil) ?? "Location",
                    subtitle: (subtitle?.isEmpty == false ? subtitle : nil)
                )
            )
        }

        return options.sorted { lhs, rhs in
            lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    private static func normalizedSkuType(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        if trimmed.lowercased() == "general" {
            return nil
        }
        return trimmed
    }
}

struct NoteDayGroup: Identifiable {
    let id = UUID()
    let dateLabel: String
    let notes: [Note]
}

private struct RunNoteComposer: View {
    @ObservedObject var viewModel: RunNotesViewModel
    @Binding var isPresented: Bool
    let editingNote: Note?
    let onNoteSaved: () -> Void

    @State private var bodyText: String
    @State private var searchText = ""
    @State private var selectedTag: NoteTagOption?
    @State private var searchTask: Task<Void, Never>?

    init(
        viewModel: RunNotesViewModel,
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

    private var filteredTags: [NoteTagOption] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else {
            return viewModel.tagOptions
        }

        return viewModel.tagOptions.filter { option in
            option.label.localizedCaseInsensitiveContains(trimmedSearch)
                || (option.subtitle?.localizedCaseInsensitiveContains(trimmedSearch) == true)
        }
    }

    private var isSaveDisabled: Bool {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedTag == nil || viewModel.isSaving
    }

    var body: some View {
        let isEditing = editingNote != nil

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
                            Text("Add context about this run…")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 12)
                        }
                    }
                }

                if !isEditing {
                    Section("Apply to") {
                        TextField("Search SKUs, machines, or locations", text: $searchText)
                            .textFieldStyle(.roundedBorder)

                        if viewModel.tagOptions.isEmpty {
                            Text("Tags are unavailable until the run details finish loading.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else if filteredTags.isEmpty {
                            Text("No tags match your search.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(filteredTags) { option in
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
                                if editingNote != nil {
                                    // keep composer clean next open
                                }
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
