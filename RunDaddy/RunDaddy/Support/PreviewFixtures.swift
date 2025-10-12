//
//  PreviewFixtures.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Foundation
import SwiftData

enum PreviewFixtures {
    private static let shared = makeFixtures()

    private struct FixtureBundle {
        let container: ModelContainer
        let runs: [Run]
    }

    private static func makeFixtures() -> FixtureBundle {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Run.self, InventoryItem.self, configurations: configuration)
        let context = container.mainContext

        let sampleRun = Run(name: "Sample Run")
        context.insert(sampleRun)

        let items = [
            InventoryItem(code: "A1", name: "Item A", count: 2, category: "Socks", run: sampleRun),
            InventoryItem(code: "B1", name: "Item B", count: 5, category: "Snacks", run: sampleRun),
            InventoryItem(code: "C1", name: "Item C", count: 1, category: "srfdg", run: sampleRun),
            InventoryItem(code: "C1", name: "Item C", count: 1, category: "dgbgbd", run: sampleRun),
            InventoryItem(code: "C1", name: "Item C", count: 1, category: "dgbgbd", run: sampleRun),
            InventoryItem(code: "C1", name: "Item C", count: 1, category: "srfsrfg", run: sampleRun),
            InventoryItem(code: "C1", name: "Item C", count: 1, category: "dgnbfghn", run: sampleRun),
            InventoryItem(code: "C1", name: "Item C", count: 1, category: "srfsgrd", run: sampleRun),
            InventoryItem(code: "C1", name: "Item C", count: 1, category: "fgnhfnhg", run: sampleRun),
            InventoryItem(code: "C1", name: "Item C", count: 1, category: "srgrg", run: sampleRun),
            InventoryItem(code: "C1", name: "Item C", count: 1, category: "dgbgdfb", run: sampleRun),
            InventoryItem(code: "D1", name: "Item D", count: 3, category: "Socks", run: sampleRun)
        ]

        items.forEach { context.insert($0) }

        do {
            try context.save()
        } catch {
            assertionFailure("Failed to seed preview data: \(error)")
        }

        return FixtureBundle(container: container, runs: [sampleRun])
    }

    static var container: ModelContainer {
        shared.container
    }

    static var sampleRun: Run {
        shared.runs.first ?? Run(name: "Sample Run")
    }
}
