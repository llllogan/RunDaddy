import Foundation

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