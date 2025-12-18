//
//  CompanyTimezonePickerView.swift
//  PickAgent
//
//  Created by ChatGPT on 2/27/2026.
//

import SwiftUI

struct CompanyTimezoneOption: Identifiable, Equatable {
    let identifier: String
    let displayName: String

    var id: String { identifier }
}

struct CompanyTimezonePickerView: View {
    let company: CompanyInfo
    let selectedIdentifier: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var options: [CompanyTimezoneOption] {
        TimeZone.knownTimeZoneIdentifiers.compactMap { identifier in
            guard let timezone = TimeZone(identifier: identifier) else { return nil }
            let localizedName = timezone.localizedName(for: .standard, locale: .current)
                ?? timezone.localizedName(for: .generic, locale: .current)
            let displayName = localizedName?.isEmpty == false ? localizedName! : identifier
            return CompanyTimezoneOption(identifier: identifier, displayName: displayName)
        }
        .sorted { $0.displayName < $1.displayName }
    }

    private var filteredOptions: [CompanyTimezoneOption] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return options
        }

        return options.filter { option in
            option.displayName.localizedCaseInsensitiveContains(trimmedQuery)
                || option.identifier.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        List {
            if let currentSelection = displayValue(for: selectedIdentifier) {
                Section("Current Selection") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentSelection.displayName)
                                .foregroundStyle(.primary)
                            Text(currentSelection.identifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }

            Section {
                Button {
                    select(TimeZone.current.identifier)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use Device Timezone")
                                .foregroundStyle(.primary)
                            Text(TimeZone.current.identifier)
                                .font(.caption)
                        }
                        Spacer()
                        if isSelected(TimeZone.current.identifier) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.blackOnWhite)
                        }
                    }
                }
            }
            .foregroundStyle(.secondary)

            Section("Timezones") {
                ForEach(filteredOptions) { option in
                    Button {
                        select(option.identifier)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.displayName)
                                    .foregroundStyle(.primary)
                                Text(option.identifier)
                                    .font(.caption)
                            }
                            Spacer()
                            if isSelected(option.identifier) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.blackOnWhite)
                            }
                        }
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
        .navigationTitle("Company Timezone")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search timezones")
        .keyboardDismissToolbar()
    }

    private func select(_ identifier: String) {
        onSelect(identifier)
        dismiss()
    }

    private func isSelected(_ identifier: String) -> Bool {
        identifier == selectedIdentifier
    }

    private func displayValue(for identifier: String) -> CompanyTimezoneOption? {
        guard let timezone = TimeZone(identifier: identifier) else { return nil }
        let localizedName = timezone.localizedName(for: .standard, locale: .current)
            ?? timezone.localizedName(for: .generic, locale: .current)
        let displayName = localizedName?.isEmpty == false ? localizedName! : identifier
        return CompanyTimezoneOption(identifier: identifier, displayName: displayName)
    }
}

#Preview {
    NavigationStack {
        CompanyTimezonePickerView(
            company: CompanyInfo(id: "company-1", name: "Milk House", role: "owner", location: "123 Main St", timeZone: "America/Chicago"),
            selectedIdentifier: TimeZone.current.identifier,
            onSelect: { _ in }
        )
    }
}
