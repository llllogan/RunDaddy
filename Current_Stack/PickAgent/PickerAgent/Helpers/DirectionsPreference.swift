//
//  DirectionsPreference.swift
//  PickAgent
//
//  Created by ChatGPT on 5/26/2025.
//

import Foundation

enum DirectionsApp: String, CaseIterable, Identifiable {
    case appleMaps
    case waze

    static let storageKey = "preferredDirectionsApp"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMaps:
            return "Apple Maps"
        case .waze:
            return "Waze"
        }
    }

    var systemImageName: String {
        switch self {
        case .appleMaps:
            return "map"
        case .waze:
            return "car.fill"
        }
    }

    func url(for query: String) -> URL? {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        switch self {
        case .appleMaps:
            return URL(string: "https://maps.apple.com/?q=\(encodedQuery)")
        case .waze:
            return URL(string: "https://www.waze.com/ul?q=\(encodedQuery)&navigate=yes")
        }
    }
}

