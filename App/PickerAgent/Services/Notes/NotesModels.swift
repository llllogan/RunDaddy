import Foundation

enum NoteScope: String, Codable {
    case run
    case persistent
}

enum NoteTargetType: String, Codable {
    case sku
    case machine
    case location
}

struct NoteTarget: Codable, Equatable {
    let type: NoteTargetType
    let id: String
    let label: String
    let subtitle: String?
}

struct Note: Codable, Identifiable, Equatable {
    let id: String
    let body: String
    let runId: String?
    let createdAt: Date
    let scope: NoteScope
    let target: NoteTarget
}

struct NotesResponse: Codable {
    let total: Int
    let notes: [Note]
}

struct CreateNoteRequest: Encodable {
    let body: String
    let runId: String?
    let targetType: NoteTargetType
    let targetId: String
}

struct UpdateNoteRequest: Encodable {
    let body: String?
    let targetType: NoteTargetType?
    let targetId: String?
}

struct NoteTagOption: Identifiable, Equatable {
    let id: String
    let type: NoteTargetType
    let label: String
    let subtitle: String?
}
