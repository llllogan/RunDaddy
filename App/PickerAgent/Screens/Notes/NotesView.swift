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

struct NotesView: View {
    @StateObject private var viewModel: NotesViewModel
    let onNotesUpdated: ((Int) -> Void)?
    @State private var composerIntent: NoteComposerIntent?
    @State private var selectedNoteForPreview: Note?
    @State private var isPreviewReadOnly = true
    let session: AuthSession
    @State private var activeFilterTag: NoteTagOption?
    @State private var activeFilterPickerType: NoteTargetType?

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
            wrappedValue: NotesViewModel(
                mode: .company,
                session: session,
                runId: nil,
                runDetail: nil,
                notesService: notesService,
                searchService: searchService,
                runsService: runsService
            )
        )
        self.onNotesUpdated = onNotesUpdated
    }

    init(
        runId: String,
        session: AuthSession,
        runDetail: RunDetail?,
        notesService: NotesServicing? = nil,
        searchService: SearchServicing? = nil,
        runsService: RunsServicing? = nil,
        onNotesUpdated: ((Int) -> Void)? = nil
    ) {
        self.session = session
        _viewModel = StateObject(
            wrappedValue: NotesViewModel(
                mode: .run,
                session: session,
                runId: runId,
                runDetail: runDetail,
                filterTag: nil,
                tagOptions: [],
                allowsRunAssociation: true,
                notesService: notesService,
                searchService: searchService,
                runsService: runsService
            )
        )
        self.onNotesUpdated = onNotesUpdated
    }

    init(
        scopedTag: NoteTagOption,
        session: AuthSession,
        runId: String?,
        tagOptions: [NoteTagOption],
        notesService: NotesServicing? = nil,
        searchService: SearchServicing? = nil,
        runsService: RunsServicing? = nil,
        onNotesUpdated: ((Int) -> Void)? = nil
    ) {
        self.session = session
        _viewModel = StateObject(
            wrappedValue: NotesViewModel(
                mode: .scoped,
                session: session,
                runId: runId,
                runDetail: nil,
                filterTag: scopedTag,
                tagOptions: tagOptions,
                allowsRunAssociation: runId != nil,
                notesService: notesService,
                searchService: searchService,
                runsService: runsService
            )
        )
        self.onNotesUpdated = onNotesUpdated
    }

    private var isCompanyMode: Bool {
        viewModel.mode == .company
    }

    private var currentFilterTag: NoteTagOption? {
        if viewModel.mode == .scoped {
            return viewModel.filterTag
        }

        if isCompanyMode {
            return activeFilterTag
        }

        return nil
    }

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.notes.isEmpty {
                Section {
                    LoadingNotesRow(message: "Loading notes…")
                }
            } else if viewModel.notes.isEmpty {
                Section {
                    Text(isCompanyMode
                         ? (activeFilterTag == nil ? "No notes have been created yet." : "No notes found for this item.")
                         : (viewModel.mode == .run ? "No notes have been added to this run yet." : "No notes found for this item.")
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                }
            } else {
                ForEach(viewModel.groupedNotes, id: \.dateLabel) { group in
                    NotesSection(
                        group: group,
                        runDateProvider: { note in
                            runDate(for: note)
                        },
                        onSelect: { note in
                            selectedNoteForPreview = note
                            isPreviewReadOnly = true
                        },
                        onEdit: { note in composerIntent = .edit(note) },
                        onDelete: { note in handleDelete(note) }
                    )
                }

                if isCompanyMode && viewModel.hasMoreNotes {
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
        .navigationBarTitleDisplayMode(isCompanyMode ? .large : .inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isCompanyMode {
                    Menu {
                        Button(selectedFilterLabel(for: .sku)) {
                            activeFilterPickerType = .sku
                        }
                        Button(selectedFilterLabel(for: .machine)) {
                            activeFilterPickerType = .machine
                        }
                        Button(selectedFilterLabel(for: .location)) {
                            activeFilterPickerType = .location
                        }

                        if activeFilterTag != nil {
                            Divider()
                            Button("Clear Filter", role: .destructive) {
                                activeFilterTag = nil
                                Task { await viewModel.loadNotes(force: true, filterTag: nil) }
                            }
                        }
                    } label: {
                        FilterToolbarButton(
                            label: "Filter Notes",
                            systemImage: "line.3.horizontal.decrease",
                            isActive: activeFilterTag != nil
                        )
                    }
                }

                Button {
                    composerIntent = .add
                } label: {
                    Label("Add Note", systemImage: "plus")
                }
                .disabled(viewModel.isAddDisabled)
            }
        }
        .refreshable {
            await viewModel.loadNotes(force: true, filterTag: currentFilterTag)
        }
        .task {
            await viewModel.loadNotes(filterTag: currentFilterTag)
            if isCompanyMode {
                await viewModel.loadSuggestedTags()
            }
        }
        .onChange(of: session.credentials.accessToken) {
            viewModel.resetSession(session)
            Task {
                await viewModel.loadNotes(force: true, filterTag: currentFilterTag)
                if isCompanyMode {
                    await viewModel.loadSuggestedTags()
                }
            }
        }
        .onChange(of: viewModel.total) { _, newValue in
            onNotesUpdated?(newValue)
        }
        .sheet(item: $composerIntent) { intent in
            NotesComposer(
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
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedNoteForPreview, onDismiss: {
            isPreviewReadOnly = true
        }) { note in
            NotesComposer(
                viewModel: viewModel,
                isPresented: Binding(
                    get: { selectedNoteForPreview != nil },
                    set: { isPresented in
                        if !isPresented {
                            selectedNoteForPreview = nil
                        }
                    }
                ),
                editingNote: note,
                isReadOnly: isPreviewReadOnly,
                onRequestEdit: {
                    isPreviewReadOnly = false
                },
                onRequestDelete: {
                    await handleDeleteFromPreview(note)
                },
                onCancel: {
                    isPreviewReadOnly = true
                },
                onSaveComplete: {
                    selectedNoteForPreview = nil
                    isPreviewReadOnly = true
                },
                onNoteSaved: {
                    onNotesUpdated?(viewModel.total)
                }
            )
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $activeFilterPickerType) { targetType in
            NotesTargetFilterPickerSheet(
                session: session,
                targetType: targetType,
                selectedTag: $activeFilterTag,
                onSelected: { tag in
                    activeFilterTag = tag
                    Task { await viewModel.loadNotes(force: true, filterTag: tag) }
                }
            )
            .presentationDragIndicator(.visible)
        }
    }

    private func handleDelete(_ note: Note) {
        Task {
            _ = await viewModel.delete(note: note)
            onNotesUpdated?(viewModel.total)
        }
    }

    private func runDate(for note: Note) -> Date? {
        switch viewModel.mode {
        case .company:
            guard let runId = note.runId else { return nil }
            return viewModel.runDates[runId]
        case .run:
            return viewModel.runDate
        case .scoped:
            return nil
        }
    }

    private func selectedFilterLabel(for type: NoteTargetType) -> String {
        guard let activeFilterTag, activeFilterTag.type == type else {
            switch type {
            case .sku: return "SKU"
            case .machine: return "Machine"
            case .location: return "Location"
            case .general: return "General"
            }
        }
        return activeFilterTag.label
    }

    private func handleDeleteFromPreview(_ note: Note) async {
        _ = await viewModel.delete(note: note)
        await MainActor.run {
            selectedNoteForPreview = nil
            onNotesUpdated?(viewModel.total)
        }
    }
}

private struct NotesSection: View {
    let group: NoteDayGroup
    let runDateProvider: (Note) -> Date?
    let onSelect: (Note) -> Void
    let onEdit: (Note) -> Void
    let onDelete: (Note) -> Void

    var body: some View {
        Section(group.dateLabel) {
            ForEach(group.notes) { note in
                NoteRowView(note: note, runDate: runDateProvider(note))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(note)
                    }
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
}

@MainActor
final class NotesViewModel: ObservableObject {
    enum Mode {
        case company
        case run
        case scoped
    }

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
    @Published private(set) var tagOptions: [NoteTagOption] = []

    let mode: Mode
    let runId: String?
    let runDate: Date?
    let filterTag: NoteTagOption?
    let allowsRunAssociation: Bool

    private var session: AuthSession
    private let notesService: NotesServicing
    private let searchService: SearchServicing
    private let runsService: RunsServicing
    private var failedRunIds = Set<String>()
    private let pageSize = 100

    init(
        mode: Mode,
        session: AuthSession,
        runId: String?,
        runDetail: RunDetail?,
        filterTag: NoteTagOption? = nil,
        tagOptions: [NoteTagOption] = [],
        allowsRunAssociation: Bool = false,
        notesService: NotesServicing? = nil,
        searchService: SearchServicing? = nil,
        runsService: RunsServicing? = nil
    ) {
        self.mode = mode
        self.session = session
        self.runId = runId
        self.runDate = runDetail?.runDate
        self.filterTag = filterTag
        self.allowsRunAssociation = allowsRunAssociation
        self.notesService = notesService ?? NotesService()
        self.searchService = searchService ?? SearchService()
        self.runsService = runsService ?? RunsService()
        if mode == .run {
            self.tagOptions = NotesViewModel.buildTagOptions(from: runDetail)
        } else if mode == .scoped {
            self.tagOptions = tagOptions
        }
    }

    var usesStaticTags: Bool {
        mode == .run || mode == .scoped
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
        guard mode == .company else { return false }
        return notes.count < total
    }

    var isAddDisabled: Bool {
        usesStaticTags && tagOptions.isEmpty
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
                errorMessage = mode == .run
                    ? "We couldn't load notes for this run. Please pull to refresh."
                    : "We couldn't load notes right now. Please pull to refresh."
            }
        }

        isLoading = false
    }

    func loadMoreNotes(filterTag: NoteTagOption? = nil) async {
        guard mode == .company else { return }
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

    func addNote(body: String, tag: NoteTagOption, associateWithRun: Bool = true) async -> Note? {
        if isSaving {
            return nil
        }

        isSaving = true
        defer { isSaving = false }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let isGeneral = tag.type == .general
            let shouldAssociate = associateWithRun && allowsRunAssociation
            let request = CreateNoteRequest(
                body: trimmedBody,
                runId: shouldAssociate ? runId : nil,
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
        guard mode == .company else { return }
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
        guard mode == .company else { return }
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
        if mode == .run, let runId {
            return try await notesService.fetchNotes(
                runId: runId,
                includePersistentForRun: true,
                recentDays: nil,
                limit: 50,
                offset: nil,
                credentials: session.credentials
            )
        }

        if mode == .scoped, let filterTag {
            return try await notesService.fetchNotes(
                targetType: filterTag.type,
                targetId: filterTag.id,
                limit: pageSize,
                offset: offset,
                credentials: session.credentials
            )
        }

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
        guard mode == .company else { return }
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

    static func buildTagOptions(from detail: RunDetail?) -> [NoteTagOption] {
        guard let detail else { return [] }

        var options: [NoteTagOption] = []
        var seen = Set<String>()

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

    static func buildTagOptions(from detail: RunLocationDetail) -> [NoteTagOption] {
        var options: [NoteTagOption] = []
        var seen = Set<String>()

        if let location = detail.section.location {
            let title = location.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = location.address?.trimmingCharacters(in: .whitespacesAndNewlines)
            seen.insert(location.id)
            options.append(
                NoteTagOption(
                    id: location.id,
                    type: .location,
                    label: (title?.isEmpty == false ? title : nil) ?? "Location",
                    subtitle: (subtitle?.isEmpty == false ? subtitle : nil)
                )
            )
        }

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

extension NoteTargetType: Identifiable {
    var id: String { rawValue }
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
    @FocusState private var isSearchFocused: Bool

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
                        .focused($isSearchFocused)
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
                    Button { dismiss() } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
            }
            .keyboardDismissToolbar()
            .onDisappear {
                searchDebounceTask?.cancel()
            }
            .task {
                isSearchFocused = true
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

private struct NotesComposer: View {
    @ObservedObject var viewModel: NotesViewModel
    @Binding var isPresented: Bool
    let editingNote: Note?
    let isReadOnly: Bool
    let onRequestEdit: (() -> Void)?
    let onRequestDelete: (() async -> Void)?
    let onCancel: (() -> Void)?
    let onSaveComplete: (() -> Void)?
    let onNoteSaved: () -> Void

    @FocusState private var isBodyFocused: Bool
    @State private var bodyText: String
    @State private var searchText = ""
    @State private var selectedTag: NoteTagOption?
    @State private var searchTask: Task<Void, Never>?
    @State private var isShowingGeneralConfirm = false
    @State private var isShowingDeleteConfirm = false
    @State private var savedBodyText: String
    @State private var savedTag: NoteTagOption?
    @State private var addToFutureRuns = false

    init(
        viewModel: NotesViewModel,
        isPresented: Binding<Bool>,
        editingNote: Note?,
        isReadOnly: Bool = false,
        onRequestEdit: (() -> Void)? = nil,
        onRequestDelete: (() async -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onSaveComplete: (() -> Void)? = nil,
        onNoteSaved: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self._isPresented = isPresented
        self.editingNote = editingNote
        self.isReadOnly = isReadOnly
        self.onRequestEdit = onRequestEdit
        self.onRequestDelete = onRequestDelete
        self.onCancel = onCancel
        self.onSaveComplete = onSaveComplete
        self.onNoteSaved = onNoteSaved
        let initialBody = editingNote?.body ?? ""
        _bodyText = State(initialValue: initialBody)
        _savedBodyText = State(initialValue: initialBody)
        if let editingNote {
            let initialTag = NoteTagOption(
                id: editingNote.target.id,
                type: editingNote.target.type,
                label: editingNote.target.label,
                subtitle: editingNote.target.subtitle
            )
            _selectedTag = State(initialValue: initialTag)
            _savedTag = State(initialValue: initialTag)
            _addToFutureRuns = State(initialValue: editingNote.runId == nil)
        } else {
            _selectedTag = State(initialValue: nil)
            _savedTag = State(initialValue: nil)
            _addToFutureRuns = State(initialValue: false)
        }
    }

    private var isEditing: Bool {
        editingNote != nil
    }

    private var isRunMode: Bool {
        viewModel.usesStaticTags
    }

    private var visibleTags: [NoteTagOption] {
        if isRunMode {
            let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSearch.isEmpty else {
                return viewModel.tagOptions
            }

            return viewModel.tagOptions.filter { option in
                option.label.localizedCaseInsensitiveContains(trimmedSearch)
                    || (option.subtitle?.localizedCaseInsensitiveContains(trimmedSearch) == true)
            }
        }

        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return viewModel.tagSuggestions
        }
        return viewModel.tagResults
    }

    private var isSaveDisabled: Bool {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSaving
    }

    private var runAssociationFooterText: String {
        if addToFutureRuns {
            return "This note will appear in future runs when \(tagScopeLabel) is present. It can also be found in the notes tab."
        }
        return "This note will only appear for this run. It can still be found later in the notes tab."
    }

    private var tagScopeLabel: String {
        switch selectedTag?.type {
        case .location:
            return "this location"
        case .machine:
            return "this machine"
        case .sku:
            return "this SKU"
        default:
            return "this item"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEditing || isReadOnly {
                    fullScreenEditor
                } else {
                    notesList.listStyle(.insetGrouped)
                }
            }
            .navigationTitle(isReadOnly ? "Note" : (editingNote == nil ? "Add Note" : "Edit Note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isReadOnly {
                    if onRequestDelete != nil {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .destructive) {
                                isShowingDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    if onRequestEdit != nil {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                onRequestEdit?()
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            resetComposerState()
                            if let onCancel {
                                onCancel()
                            } else {
                                isPresented = false
                            }
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button {
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
                                    note = await viewModel.addNote(
                                        body: bodyText,
                                        tag: tag,
                                        associateWithRun: !addToFutureRuns
                                    )
                                }
                                if note != nil {
                                    savedBodyText = bodyText
                                    savedTag = selectedTag
                                    onNoteSaved()
                                    if let onSaveComplete {
                                        onSaveComplete()
                                    } else {
                                        isPresented = false
                                        resetComposerState()
                                    }
                                }
                            }
                        } label: {
                            Label("Save", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaveDisabled)
                    }

                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button {
                            UIApplication.shared.dismissKeyboard()
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                        }
                        .accessibilityLabel("Dismiss Keyboard")
                    }
                }
            }
        }
        .alert("Delete note?", isPresented: $isShowingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await onRequestDelete?()
                }
            }
        } message: {
            Text("Are you sure you want to delete this note?")
        }
        .alert("No tag selected", isPresented: $isShowingGeneralConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Yes") {
                Task {
                    let tag = NoteTagOption(id: "general", type: .general, label: "General", subtitle: nil)
                    let note = await viewModel.addNote(body: bodyText, tag: tag, associateWithRun: !addToFutureRuns)
                    if note != nil {
                        savedBodyText = bodyText
                        savedTag = selectedTag
                        onNoteSaved()
                        if let onSaveComplete {
                            onSaveComplete()
                        } else {
                            isPresented = false
                            resetComposerState()
                        }
                    }
                }
            }
        } message: {
            Text("Are you sure you dont want to tag this note with a SKU, machine, or location?")
        }
        .task {
            guard !isEditing, !isReadOnly else { return }
            await MainActor.run {
                isBodyFocused = true
            }
        }
        .onChange(of: isReadOnly) { _, newValue in
            guard !newValue else { return }
            Task { @MainActor in
                isBodyFocused = true
            }
        }
    }

    private var fullScreenEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $bodyText)
                .focused($isBodyFocused)
                .disabled(isReadOnly)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            if bodyText.isEmpty {
                Text("Add context or reminders for your team…")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
        }
    }

    private var notesList: some View {
        List {
            Section {
                ZStack(alignment: .topLeading) {
                    if isReadOnly {
                        TextEditor(text: $bodyText)
                            .disabled(true)
                    } else {
                        TextEditor(text: $bodyText)
                            .focused($isBodyFocused)

                        if bodyText.isEmpty {
                            Text("Add context or reminders for your team…")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 10)
                        }
                    }
                }
            }

            if !isEditing && viewModel.allowsRunAssociation && !isReadOnly {
                Section {
                    Toggle("Add to future runs", isOn: $addToFutureRuns)
                } footer: {
                    Text(runAssociationFooterText)
                }
            }

            if !isEditing {
                Section("Apply to") {
                    TextField("Search SKUs, machines, or locations", text: $searchText)
                        .disabled(isReadOnly)
                        .onChange(of: searchText) { _, newValue in
                            handleSearchChange(newValue)
                        }

                    if isRunMode {
                        if viewModel.tagOptions.isEmpty {
                            Text("Tags are unavailable until the run details finish loading.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else if visibleTags.isEmpty {
                            Text("No tags match your search.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
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
                                .disabled(isReadOnly)
                            }
                        }
                    } else {
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
                                .disabled(isReadOnly)
                            }
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
    }

    private func handleSearchChange(_ newValue: String) {
        guard !isReadOnly else { return }
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if isRunMode {
            return
        }

        searchTask?.cancel()
        guard trimmed.count >= 2 else {
            viewModel.clearSearchResults()
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await viewModel.searchTags(matching: trimmed)
        }
    }

    private func resetComposerState() {
        bodyText = savedBodyText
        searchText = ""
        selectedTag = savedTag
        addToFutureRuns = false
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
