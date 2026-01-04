import SwiftUI
import Combine

struct ExpiriesView: View {
    let session: AuthSession

    @StateObject private var viewModel: ExpiriesViewModel
    private let runsService: RunsServicing

    @State private var isPerformingAction = false
    @State private var actionAlertMessage: String?
    @State private var isShowingActionAlert = false

    @State private var pendingRunOptions: [UpcomingExpiringItemsResponse.Section.RunOption] = []
    @State private var pendingAddToRunItem: UpcomingExpiringItemsResponse.Section.Item?
    @State private var isShowingRunPicker = false
    @State private var isHidingIgnored = true

    init(session: AuthSession, service: ExpiriesServicing? = nil, runsService: RunsServicing? = nil) {
        self.session = session
        self.runsService = runsService ?? RunsService()
        _viewModel = StateObject(
            wrappedValue: ExpiriesViewModel(
                session: session,
                service: service ?? ExpiriesService()
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.response == nil {
                ContentUnavailableView("Loading Expiries…", systemImage: "calendar.badge.exclamationmark")
            } else if let errorMessage = viewModel.errorMessage, viewModel.response == nil {
                ContentUnavailableView(
                    "Expiries",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if let response = viewModel.response {
                let sections = visibleSections
                if sections.isEmpty {
                    ContentUnavailableView(
                        "No Expiries",
                        systemImage: "checkmark.circle",
                        description: Text("Nothing is expiring in the next two weeks.")
                    )
                } else {
                    List {
                        ForEach(sections) { section in
                            Section(header: sectionHeaderView(for: section)) {
                                ForEach(section.items) { item in
                                    expiringItemRow(item: item, section: section)
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Expiries",
                    systemImage: "exclamationmark.triangle",
                    description: Text("We couldn't load expiries right now.")
                )
            }
        }
        .navigationTitle("Expiries")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isHidingIgnored = true
                    } label: {
                        if isHidingIgnored {
                            Label("Hide Ignored Items", systemImage: "checkmark")
                        } else {
                            Text("Hide Ignored Items")
                        }
                    }

                    Button {
                        isHidingIgnored = false
                    } label: {
                        if !isHidingIgnored {
                            Label("Show Ignored Items", systemImage: "checkmark")
                        } else {
                            Text("Show Ignored Items")
                        }
                    }
                } label: {
                    FilterToolbarButton(
                        label: "Filter Expiries",
                        systemImage: "line.3.horizontal.decrease",
                        isActive: isHidingIgnored
                    )
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load(force: true)
        }
        .alert("Expiries", isPresented: $isShowingActionAlert) {
            Button("OK") {
                actionAlertMessage = nil
            }
        } message: {
            Text(actionAlertMessage ?? "")
        }
        .confirmationDialog(
            "Add to which run?",
            isPresented: $isShowingRunPicker,
            titleVisibility: .visible
        ) {
            ForEach(pendingRunOptions) { run in
                Button(runPickerTitle(for: run)) {
                    if let item = pendingAddToRunItem {
                        createPickEntry(run: run, item: item)
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                pendingRunOptions = []
                pendingAddToRunItem = nil
            }
        } message: {
            Text(runPickerMessage())
        }
    }

    private var visibleSections: [UpcomingExpiringItemsResponse.Section] {
        guard let response = viewModel.response else {
            return []
        }

        guard isHidingIgnored else {
            return response.sections
        }

        return response.sections.compactMap { section in
            let items = section.items.filter { !$0.isIgnored }
            guard !items.isEmpty else {
                return nil
            }
            return UpcomingExpiringItemsResponse.Section(expiryDate: section.expiryDate, items: items, runs: section.runs)
        }
    }

    private func sectionHeaderText(_ expiryDate: String) -> String {
        let formatter = Self.expiryFormatter
        guard let date = formatter.date(from: expiryDate) else {
            return expiryDate
        }

        let calendar = Calendar.current
        let dayTitle: String
        if calendar.isDateInToday(date) {
            dayTitle = "Today"
        } else if calendar.isDateInTomorrow(date) {
            dayTitle = "Tomorrow"
        } else {
            dayTitle = Self.weekdayFormatter.string(from: date)
        }

        let dayNumber = Self.dayFormatter.string(from: date)
        let month = Self.monthFormatter.string(from: date).pascalCased
        return "\(dayTitle)  \(dayNumber) \(month)"
    }

    private func stockingStatus(
        for item: UpcomingExpiringItemsResponse.Section.Item,
        section: UpcomingExpiringItemsResponse.Section
    ) -> (message: String, color: Color) {
        guard let stockingRun = item.stockingRun else {
            if section.runs.isEmpty {
                return (message: "", color: .secondary)
            }
            return (message: "Not stocked in a run", color: .red)
        }

        return (message: "\(item.plannedQuantity) will be stocked, need \(item.expiringQuantity) more", color: .secondary)
    }

    private func machineDisplayName(for item: UpcomingExpiringItemsResponse.Section.Item) -> String {
        let description = item.machine.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return description.isEmpty ? item.machine.code : description
    }

    private func itemLabel(for count: Int) -> String {
        count == 1 ? "item" : "items"
    }

    private func noRunsScheduledMessage(for expiryDate: String) -> String {
        guard let date = Self.expiryFormatter.date(from: expiryDate) else {
            return "No runs are scheduled for \(expiryDate)."
        }

        let day = Calendar.current.component(.day, from: date)
        let dayOrdinal =
            Self.ordinalFormatter.string(from: NSNumber(value: day)) ??
            Self.dayFormatter.string(from: date)
        let month = Self.monthFormatter.string(from: date).pascalCased
        return "No runs are scheduled for the \(dayOrdinal) of \(month)"
    }

    @ViewBuilder
    private func sectionHeaderView(for section: UpcomingExpiringItemsResponse.Section) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sectionHeaderText(section.expiryDate))
            if section.runs.isEmpty {
                Text(noRunsScheduledMessage(for: section.expiryDate))
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func expiringItemRow(
        item: UpcomingExpiringItemsResponse.Section.Item,
        section: UpcomingExpiringItemsResponse.Section
    ) -> some View {
        let stockingStatus = item.isIgnored
            ? (message: "Ignored", color: Color.red)
            : stockingStatus(for: item, section: section)
        let baseRow = ExpiringItemRowView(
            skuName: item.sku.name,
            skuType: item.sku.type,
            machineCode: item.machine.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? item.machine.description!
                : item.machine.code,
            coilCode: item.coil.code,
            quantity: item.expiringQuantity,
            stockingMessage: stockingStatus.message,
            stockingMessageColor: stockingStatus.color
        )

        let row = baseRow.swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if item.isIgnored {
                Button {
                    undoIgnore(item: item, expiryDate: section.expiryDate)
                } label: {
                    Label("Undo Ignore", systemImage: "arrow.uturn.left")
                }
                .tint(.blue)
                .disabled(isPerformingAction)
            } else {
                Button {
                    ignore(item: item, expiryDate: section.expiryDate)
                } label: {
                    Label("Ignore", systemImage: "eye.slash")
                }
                .tint(.gray)
                .disabled(isPerformingAction)
            }
        }

        if item.isIgnored {
            row
        } else if let stockingRun = item.stockingRun {
            row.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    addNeeded(runId: stockingRun.id, item: item)
                } label: {
                    Label("Add \(item.expiringQuantity) to coil", systemImage: "plus")
                }
                .tint(.blue)
                .disabled(isPerformingAction)
            }
        } else if !section.runs.isEmpty {
            row.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    addToRun(item: item, runOptions: section.runs)
                } label: {
                    Label("Add to Run", systemImage: "plus")
                }
                .tint(.orange)
                .disabled(isPerformingAction)
            }
        } else {
            row
        }
    }

    private func addNeeded(runId: String, item: UpcomingExpiringItemsResponse.Section.Item) {
        guard !isPerformingAction else {
            return
        }

        isPerformingAction = true
        Task { @MainActor in
            defer { isPerformingAction = false }
            do {
                let result = try await runsService.addNeededForExpiringItem(
                    runId: runId,
                    coilItemId: item.coilItemId,
                    credentials: session.credentials
                )
                let machineName = machineDisplayName(for: item)
                actionAlertMessage = "Added \(result.addedQuantity) \(itemLabel(for: result.addedQuantity)) to \(machineName) for \(sectionHeaderText(result.runDate))."
                isShowingActionAlert = true
                await viewModel.load(force: true)
            } catch {
                actionAlertMessage = "We couldn't add expiring items right now. Please try again."
                isShowingActionAlert = true
            }
        }
    }

    private func addToRun(item: UpcomingExpiringItemsResponse.Section.Item, runOptions: [UpcomingExpiringItemsResponse.Section.RunOption]) {
        guard !isPerformingAction else {
            return
        }

        guard !runOptions.isEmpty else {
            actionAlertMessage = "No runs are scheduled for that day."
            isShowingActionAlert = true
            return
        }

        if let match = runOptions.first(where: { run in
            if run.machineIds.contains(item.machine.id) {
                return true
            }
            if let locationId = item.machine.locationId, run.locationIds.contains(locationId) {
                return true
            }
                return false
        }) {
            createPickEntry(run: match, item: item)
            return
        }

        pendingRunOptions = runOptions
        pendingAddToRunItem = item
        isShowingRunPicker = true
    }

    private func createPickEntry(run: UpcomingExpiringItemsResponse.Section.RunOption, item: UpcomingExpiringItemsResponse.Section.Item) {
        guard !isPerformingAction else {
            return
        }

        isPerformingAction = true
        Task { @MainActor in
            defer {
                isPerformingAction = false
                pendingRunOptions = []
                pendingAddToRunItem = nil
            }

            do {
                try await runsService.createPickEntry(
                    runId: run.id,
                    coilItemId: item.coilItemId,
                    count: item.expiringQuantity,
                    credentials: session.credentials
                )
                let machineName = machineDisplayName(for: item)
                actionAlertMessage = "Added \(item.expiringQuantity) \(itemLabel(for: item.expiringQuantity)) to \(machineName) for \(sectionHeaderText(run.runDate))."
                isShowingActionAlert = true
                await viewModel.load(force: true)
            } catch {
                actionAlertMessage = "We couldn't add this to a run right now. Please try again."
                isShowingActionAlert = true
            }
        }
    }

    private func runPickerTitle(for run: UpcomingExpiringItemsResponse.Section.RunOption) -> String {
        let locationNames = run.locations
            .compactMap { ($0.name ?? $0.address)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if locationNames.isEmpty {
            return "Run locations unavailable"
        }

        let summary = locationNames.prefix(2).joined(separator: ", ")
        let suffix = locationNames.count > 2 ? " +\(locationNames.count - 2)" : ""
        return "\(summary)\(suffix)"
    }

    private func runPickerMessage() -> String {
        if pendingRunOptions.isEmpty {
            return ""
        }
        return "Select a run to add this coil to. Runs are listed with their locations."
    }

    private func ignore(item: UpcomingExpiringItemsResponse.Section.Item, expiryDate: String) {
        guard !isPerformingAction else {
            return
        }

        isPerformingAction = true
        Task { @MainActor in
            defer { isPerformingAction = false }
            do {
                try await viewModel.ignoreExpiry(item: item, expiryDate: expiryDate)
                await viewModel.load(force: true)
            } catch {
                actionAlertMessage = "We couldn't ignore that expiry right now. Please try again."
                isShowingActionAlert = true
            }
        }
    }

    private func undoIgnore(item: UpcomingExpiringItemsResponse.Section.Item, expiryDate: String) {
        guard !isPerformingAction else {
            return
        }

        isPerformingAction = true
        Task { @MainActor in
            defer { isPerformingAction = false }
            do {
                try await viewModel.undoIgnoreExpiry(item: item, expiryDate: expiryDate)
                await viewModel.load(force: true)
            } catch {
                actionAlertMessage = "We couldn't undo that ignore right now. Please try again."
                isShowingActionAlert = true
            }
        }
    }

    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "dd"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .ordinal
        return formatter
    }()
}

private extension String {
    var pascalCased: String {
        guard let firstCharacter = first else {
            return self
        }

        return firstCharacter.uppercased() + dropFirst().lowercased()
    }
}

@MainActor
final class ExpiriesViewModel: ObservableObject {
    @Published private(set) var response: UpcomingExpiringItemsResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var session: AuthSession
    private let service: ExpiriesServicing

    init(session: AuthSession, service: ExpiriesServicing) {
        self.session = session
        self.service = service
    }

    func load(force: Bool = false) async {
        if isLoading && !force {
            return
        }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            response = try await service.fetchUpcomingExpiries(daysAhead: 14, credentials: session.credentials)
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let serviceError = error as? ExpiriesServiceError {
                errorMessage = serviceError.localizedDescription
            } else {
                errorMessage = "We couldn't load expiries right now. Please try again."
            }
            response = nil
        }
    }

    func ignoreExpiry(item: UpcomingExpiringItemsResponse.Section.Item, expiryDate: String) async throws {
        try await service.ignoreExpiry(
            coilItemId: item.coilItemId,
            expiryDate: expiryDate,
            quantity: item.expiringQuantity,
            credentials: session.credentials
        )
    }

    func undoIgnoreExpiry(item: UpcomingExpiringItemsResponse.Section.Item, expiryDate: String) async throws {
        try await service.undoIgnoreExpiry(
            coilItemId: item.coilItemId,
            expiryDate: expiryDate,
            credentials: session.credentials
        )
    }
}
