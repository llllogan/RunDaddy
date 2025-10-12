//
//  InventoryItem.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Foundation
import SwiftData

@Model
final class InventoryItem {
    var name: String
    var count: Int
    @Relationship(inverse: \Run.items)
    var run: Run

    init(name: String, count: Int, run: Run) {
        self.name = name
        self.count = count
        self.run = run
    }
}
