//
//  Machine.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Foundation
import SwiftData

@Model
final class Machine {
    @Attribute(.unique) var id: String
    var name: String
    var locationLabel: String?
    @Relationship(inverse: \Location.machines) var location: Location?
    @Relationship(deleteRule: .cascade) var coils: [Coil] = []

    init(id: String,
         name: String,
         locationLabel: String? = nil,
         location: Location? = nil,
         coils: [Coil] = []) {
        self.id = id
        self.name = name
        self.locationLabel = locationLabel
        self.location = location
        self.coils = coils
    }
}
