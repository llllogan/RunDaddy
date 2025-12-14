import Foundation

enum SearchResultFilter: String, CaseIterable, Codable {
    case location = "LOCATION"
    case machine = "MACHINE"
    case sku = "SKU"
}

struct SearchResult: Codable, Identifiable {
    let id: String
    let type: String
    let title: String
    let subtitle: String
}

struct SearchResponse: Codable {
    let generatedAt: String
    let query: String
    let results: [SearchResult]
}
