import Foundation

protocol NotesServicing {
    func fetchNotes(
        runId: String?,
        includePersistentForRun: Bool,
        recentDays: Int?,
        limit: Int?,
        credentials: AuthCredentials
    ) async throws -> NotesResponse

    func createNote(
        request: CreateNoteRequest,
        credentials: AuthCredentials
    ) async throws -> Note

    func updateNote(
        noteId: String,
        request: UpdateNoteRequest,
        credentials: AuthCredentials
    ) async throws -> Note

    func deleteNote(
        noteId: String,
        credentials: AuthCredentials
    ) async throws
}

final class NotesService: NotesServicing {
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchNotes(
        runId: String?,
        includePersistentForRun: Bool = true,
        recentDays: Int? = nil,
        limit: Int? = nil,
        credentials: AuthCredentials
    ) async throws -> NotesResponse {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("notes")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []

        if let runId {
            queryItems.append(URLQueryItem(name: "runId", value: runId))
            if !includePersistentForRun {
                queryItems.append(URLQueryItem(name: "includePersistentForRun", value: "false"))
            }
        }

        if let recentDays {
            queryItems.append(URLQueryItem(name: "recentDays", value: String(recentDays)))
        }

        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }

        components?.queryItems = queryItems
        let resolvedURL = components?.url ?? url

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotesServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw NotesServiceError.notFound
            }
            throw NotesServiceError.serverError(code: httpResponse.statusCode)
        }

        return try decoder.decode(NotesResponse.self, from: data)
    }

    func createNote(
        request: CreateNoteRequest,
        credentials: AuthCredentials
    ) async throws -> Note {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("notes")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpShouldHandleCookies = true
        urlRequest.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotesServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw NotesServiceError.notFound
            }
            if httpResponse.statusCode == 400 {
                throw NotesServiceError.invalidRequest
            }
            throw NotesServiceError.serverError(code: httpResponse.statusCode)
        }

        return try decoder.decode(Note.self, from: data)
    }

    func updateNote(
        noteId: String,
        request: UpdateNoteRequest,
        credentials: AuthCredentials
    ) async throws -> Note {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("notes")
        url.appendPathComponent(noteId)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "PATCH"
        urlRequest.httpShouldHandleCookies = true
        urlRequest.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotesServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw NotesServiceError.notFound
            }
            if httpResponse.statusCode == 400 {
                throw NotesServiceError.invalidRequest
            }
            throw NotesServiceError.serverError(code: httpResponse.statusCode)
        }

        return try decoder.decode(Note.self, from: data)
    }

    func deleteNote(
        noteId: String,
        credentials: AuthCredentials
    ) async throws {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("notes")
        url.appendPathComponent(noteId)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "DELETE"
        urlRequest.httpShouldHandleCookies = true
        urlRequest.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await urlSession.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotesServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw NotesServiceError.notFound
            }
            throw NotesServiceError.serverError(code: httpResponse.statusCode)
        }
    }
}

enum NotesServiceError: LocalizedError {
    case invalidResponse
    case serverError(code: Int)
    case notFound
    case invalidRequest

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "We couldn't connect to RunDaddy right now. Please try again."
        case let .serverError(code):
            return "Notes request failed with an unexpected error (code \(code))."
        case .notFound:
            return "We couldn't find those notes. They may have been removed."
        case .invalidRequest:
            return "Please double-check the note details and try again."
        }
    }
}
