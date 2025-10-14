//
//  Item.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    @Attribute(.unique) var id: String
    var name: String
    var type: String
    @Relationship(deleteRule: .cascade) var coils: [Coil] = []

    init(id: String, name: String, type: String, coils: [Coil] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.coils = coils
    }
}
