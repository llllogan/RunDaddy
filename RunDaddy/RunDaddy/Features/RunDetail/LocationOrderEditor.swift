//
//  LocationOrderEditor.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI

struct LocationOrderEditor: View {
    struct Item: Identifiable, Equatable {
        let id: String
        let name: String
        var packOrder: Int
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.haptics) private var haptics
    @State private var items: [Item]
    private let onSave: ([Item]) -> Void

    init(items: [Item], onSave: @escaping ([Item]) -> Void) {
        let sorted = items.sorted { lhs, rhs in
            if lhs.packOrder == rhs.packOrder {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.packOrder < rhs.packOrder
        }
        _items = State(initialValue: sorted)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                        Text(item.name)
                    }
                }
                .onMove { indices, newOffset in
                    items.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .navigationTitle("Reorder Locations")
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        haptics.secondaryButtonTap()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        haptics.prominentActionTap()
                        saveAndDismiss()
                    }
                }
            }
        }
    }

    private func saveAndDismiss() {
        var updated = items
        for index in updated.indices {
            updated[index].packOrder = index + 1
        }
        onSave(updated)
        dismiss()
    }
}
