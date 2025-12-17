import SwiftUI
import Combine

struct ExpiriesView: View {
    let session: AuthSession

    @StateObject private var viewModel: ExpiriesViewModel

    init(session: AuthSession, service: ExpiriesServicing? = nil) {
        self.session = session
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
                if response.sections.isEmpty {
                    ContentUnavailableView(
                        "No Expiries",
                        systemImage: "checkmark.circle",
                        description: Text("Nothing is expiring in the next two weeks.")
                    )
                } else {
                    List {
                        ForEach(response.sections) { section in
                            Section(header: Text(sectionHeaderText(section.expiryDate))) {
                                ForEach(section.items) { item in
                                    let stockingStatus = stockingStatus(for: item)
                                    ExpiringItemRowView(
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
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load(force: true)
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

    private func stockingStatus(for item: UpcomingExpiringItemsResponse.Section.Item) -> (message: String, color: Color) {
        guard let stockingRun = item.stockingRun else {
            return (message: "Not stocked in a run", color: .red)
        }

        return (message: "\(item.plannedQuantity) will be stocked, need \(item.expiringQuantity) more", color: .secondary)
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
}
