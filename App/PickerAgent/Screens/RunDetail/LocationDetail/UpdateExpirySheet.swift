import SwiftUI

struct UpdateExpirySheet: View {
    let pickItem: RunDetail.PickItem
    let onDismiss: () -> Void
    let onSave: (_ expiryDate: String, _ quantity: Int) -> Void
    
    @State private var selectedDate: Date
    @State private var quantity: Int = 0
    
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
        onSave: @escaping (_ expiryDate: String, _ quantity: Int) -> Void
    ) {
        self.pickItem = pickItem
        self.onDismiss = onDismiss
        self.onSave = onSave
        
        let normalized = pickItem.expiryDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let initial = Self.expiryFormatter.date(from: normalized) ?? Date()
        _selectedDate = State(initialValue: initial)
    }
    
    private var baseExpiryDate: String {
        pickItem.expiryDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    private var selectedExpiryDateString: String {
        Self.expiryFormatter.string(from: selectedDate)
    }
    
    private var hasValidChange: Bool {
        quantity > 0 && selectedExpiryDateString != baseExpiryDate
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    DatePicker(
                        "Expiry Date",
                        selection: $selectedDate,
                        displayedComponents: [.date]
                    )
                } header: {
                    Text("New Expiry")
                } footer: {
                    Text("Current: \(baseExpiryDate)")
                }
                
                Section {
                    HStack(spacing: 12) {
                        Button {
                            quantity = max(0, quantity - 1)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                        }
                        .disabled(quantity <= 0)
                        
                        Spacer()
                        
                        Text("\(quantity)")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        
                        Spacer()
                        
                        Button {
                            quantity = min(pickItem.count, quantity + 1)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .disabled(quantity >= pickItem.count)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Count")
                } footer: {
                    Text("Select how many items in this coil have a different expiry date.")
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
                        onSave(selectedExpiryDateString, quantity)
                    }
                    .disabled(!hasValidChange)
                }
            }
        }
    }
}

