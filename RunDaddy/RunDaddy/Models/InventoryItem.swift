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
    var checked: Bool = false
    var dateAdded: Date = Date()
    var dateChecked: Date?
    @Relationship(inverse: \Run.items)
    var run: Run

    init(code: String,
         name: String,
         count: Int,
         category: String,
         checked: Bool = false,
         dateAdded: Date = Date(),
         dateChecked: Date? = nil,
         run: Run) {
        self.code = code
        self.name = name
        self.count = count
        self.category = category
        self.checked = checked
        self.dateAdded = dateAdded
        self.dateChecked = dateChecked
        self.run = run
    }
}
