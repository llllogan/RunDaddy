//
//  Run.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Foundation
import SwiftData

@Model
final class Run {
    var name: String
    @Relationship(deleteRule: .cascade)
    var items: [InventoryItem] = []

    init(name: String) {
        self.name = name
    }
}
