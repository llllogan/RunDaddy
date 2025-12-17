import SwiftUI

struct UpdateExpirySheet: View {
    struct OverridePayload: Identifiable, Equatable {
        let expiryDate: String
        let quantity: Int
        
        var id: String { expiryDate }
    }
    
    let pickItem: RunDetail.PickItem
    let onDismiss: () -> Void
    let onSave: (_ overrides: [OverridePayload]) -> Void
    
    @State private var selectedDates: [Date]
    private let initialOverridesKey: String
    
    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    init(
        pickItem: RunDetail.PickItem,
        onDismiss: @escaping () -> Void,
        onSave: @escaping (_ overrides: [OverridePayload]) -> Void
    ) {
        self.pickItem = pickItem
        self.onDismiss = onDismiss
        self.onSave = onSave
        
        let baseExpiryDate = pickItem.expiryDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let baseDate = Self.expiryFormatter.date(from: baseExpiryDate) ?? Date()
        
        var dates = Array(repeating: baseDate, count: max(0, pickItem.count))
        
        var cursor = 0
        for overrideRow in pickItem.expiryOverrides {
            let dateString = overrideRow.expiryDate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !dateString.isEmpty else { continue }
            guard let overrideDate = Self.expiryFormatter.date(from: dateString) else { continue }
            let qty = max(0, overrideRow.quantity)
            guard qty > 0 else { continue }
            
            for _ in 0..<qty {
                guard cursor < dates.count else { break }
                dates[cursor] = overrideDate
                cursor += 1
            }
        }
        
        _selectedDates = State(initialValue: dates)
        initialOverridesKey = UpdateExpirySheet.buildOverridesKey(from: dates, baseExpiryDate: baseExpiryDate)
    }
    
    private var baseExpiryDate: String {
        pickItem.expiryDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    private static func buildOverridesKey(from dates: [Date], baseExpiryDate: String) -> String {
        let base = baseExpiryDate.trimmingCharacters(in: .whitespacesAndNewlines)
        var counts: [String: Int] = [:]
        
        for date in dates {
            let label = expiryFormatter.string(from: date)
            if label == base { continue }
            counts[label, default: 0] += 1
        }
        
        return counts
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
    }
    
    private var currentOverrides: [OverridePayload] {
        let base = baseExpiryDate
        var counts: [String: Int] = [:]
        
        for date in selectedDates {
            let label = Self.expiryFormatter.string(from: date)
            if label == base { continue }
            counts[label, default: 0] += 1
        }
        
        return counts
            .sorted(by: { $0.key < $1.key })
            .map { OverridePayload(expiryDate: $0.key, quantity: $0.value) }
    }
    
    private var hasChanges: Bool {
        UpdateExpirySheet.buildOverridesKey(from: selectedDates, baseExpiryDate: baseExpiryDate) != initialOverridesKey
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(Array(selectedDates.indices), id: \.self) { index in
                        HStack {
                            Text("Item \(index + 1)")
                            
                            Spacer()
                            
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { selectedDates[index] },
                                    set: { selectedDates[index] = $0 }
                                ),
                                displayedComponents: [.date]
                            )
                            .labelsHidden()
                        }
                    }
                } header: {
                    Text("Expiry Dates")
                } footer: {
                    Text("Base expiry: \(baseExpiryDate)")
                }
            }
            .navigationTitle("Update Expiry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(currentOverrides)
                    }
                    .disabled(!hasChanges)
                }
            }
        }
    }
}

