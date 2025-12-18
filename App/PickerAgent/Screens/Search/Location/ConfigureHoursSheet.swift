import SwiftUI

struct ConfigureHoursSheet: View {
    @Binding var hasOpeningTime: Bool
    @Binding var hasClosingTime: Bool
    @Binding var openingTime: Date
    @Binding var closingTime: Date
    @Binding var dwellTimeText: String
    let isSaving: Bool
    let errorMessage: String?
    let lastSavedAt: Date?
    let onSave: () -> Void

    private var subtitle: String {
        "Configure opening and closing windows and how long pickups take."
    }

    private var formattedLastSaved: String? {
        guard let lastSavedAt else { return nil }
        return ConfigureHoursSheet.relativeFormatter.localizedString(for: lastSavedAt, relativeTo: Date())
    }

    var body: some View {
        List {
            Section {
                timeRow(title: "Opens", isEnabled: $hasOpeningTime, time: $openingTime)
                timeRow(title: "Closes", isEnabled: $hasClosingTime, time: $closingTime)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Dwell Time")
                            .font(.subheadline.weight(.semibold))
                        Text("(minutes)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField("Not set", text: $dwellTimeText)
                        .keyboardType(.numberPad)
                }
                .padding(.vertical, 4)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }

                if let formattedLastSaved {
                    Text("Saved \(formattedLastSaved)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            } footer: {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .keyboardDismissToolbar()
    }

    private func timeRow(title: String, isEnabled: Binding<Bool>, time: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Toggle(isOn: isEnabled) {
                    EmptyView()
                }
                .labelsHidden()
                .tint(.blue)
            }

            DatePicker(
                "",
                selection: time,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .disabled(!isEnabled.wrappedValue)
            .opacity(isEnabled.wrappedValue ? 1 : 0.35)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
