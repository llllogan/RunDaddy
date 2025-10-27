//
//  RunDetailNotPackedItemsView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI

struct NotPackedItemsView: View {
    @Bindable var run: Run

    private var sections: [NotPackedLocationSection] {
        RunDetailSectionsBuilder.notPackedSections(for: run)
    }

    var body: some View {
        List {
            if sections.isEmpty {
                Text("All items were packed.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sections) { section in
                    Section(section.location.name) {
                        ForEach(section.items) { runCoil in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(runCoil.coil.item.name)
                                        .font(.headline)
                                    Text(runCoil.coil.machine.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("Need \(max(runCoil.pick, 0))")
                                    .font(.headline)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Not Packed")
        .navigationBarTitleDisplayMode(.inline)
    }
}
