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
    var code: String
    var name: String
    var count: Int
    var category: String
    @Relationship(inverse: \Run.items)
    var run: Run

    init(code: String, name: String, count: Int, category: String, run: Run) {
        self.code = code
        self.name = name
        self.count = count
        self.category = category
        self.run = run
    }
}
