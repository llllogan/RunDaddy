import Foundation

protocol ExpiriesServicing {
    func fetchUpcomingExpiries(daysAhead: Int?, credentials: AuthCredentials) async throws -> UpcomingExpiringItemsResponse
}

private extension KeyedDecodingContainer {
    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let intValue = try? decode(Int.self, forKey: key) {
            return intValue
        }
        if let doubleValue = try? decode(Double.self, forKey: key) {
            return Int(doubleValue.rounded())
        }
        if let stringValue = try? decode(String.self, forKey: key) {
            return Int(stringValue)
        }
        return nil
    }

    func decodeStringOrEmpty(forKey key: Key) throws -> String {
        (try? decode(String.self, forKey: key)) ?? ""
    }
}

final class ExpiriesService: ExpiriesServicing {
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(urlSession: URLSession = .shared, decoder: JSONDecoder? = nil) {
        self.urlSession = urlSession
        let resolvedDecoder = decoder ?? JSONDecoder()
        resolvedDecoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = resolvedDecoder
    }

    func fetchUpcomingExpiries(daysAhead: Int?, credentials: AuthCredentials) async throws -> UpcomingExpiringItemsResponse {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("expiries")

        if let daysAhead {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "daysAhead", value: String(daysAhead))
            ]
            url = components?.url ?? url
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExpiriesServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            throw ExpiriesServiceError.serverError(code: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(UpcomingExpiringItemsResponse.self, from: data)
        } catch {
            throw ExpiriesServiceError.decodingFailed(underlying: error)
        }
    }
}

enum ExpiriesServiceError: LocalizedError {
    case invalidResponse
    case serverError(code: Int)
    case decodingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "We couldn't read the expiries response."
        case .serverError(let code):
            return "The server returned an error (\(code))."
        case .decodingFailed:
            return "We couldn't understand the expiries response."
        }
    }
}

struct UpcomingExpiringItemsResponse: Equatable, Decodable {
    struct Section: Equatable, Decodable, Identifiable {
        struct RunOption: Equatable, Decodable, Identifiable {
            struct Location: Equatable, Decodable {
                let id: String
                let name: String?
                let address: String?
            }

            let id: String
            let runDate: String
            let locationIds: [String]
            let machineIds: [String]
            let locations: [Location]

            private enum CodingKeys: String, CodingKey {
                case id
                case runDate
                case locationIds
                case machineIds
                case locations
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decodeStringOrEmpty(forKey: .id)
                runDate = try container.decodeStringOrEmpty(forKey: .runDate)
                locationIds = (try? container.decodeIfPresent([String].self, forKey: .locationIds)) ?? []
                machineIds = (try? container.decodeIfPresent([String].self, forKey: .machineIds)) ?? []
                locations = (try? container.decodeIfPresent([Location].self, forKey: .locations)) ?? []
            }
        }

        struct Item: Equatable, Decodable, Identifiable {
            struct Sku: Equatable, Decodable {
                let id: String
                let code: String
                let name: String
                let type: String

                private enum CodingKeys: String, CodingKey {
                    case id
                    case code
                    case name
                    case type
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    id = try container.decodeStringOrEmpty(forKey: .id)
                    code = try container.decodeStringOrEmpty(forKey: .code)
                    name = try container.decodeStringOrEmpty(forKey: .name)
                    type = try container.decodeStringOrEmpty(forKey: .type)
                }
            }

            struct Machine: Equatable, Decodable {
                let id: String
                let code: String
                let description: String?
                let locationId: String?

                private enum CodingKeys: String, CodingKey {
                    case id
                    case code
                    case description
                    case locationId
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    id = try container.decodeStringOrEmpty(forKey: .id)
                    code = try container.decodeStringOrEmpty(forKey: .code)
                    description = try? container.decodeIfPresent(String.self, forKey: .description)
                    locationId = try? container.decodeIfPresent(String.self, forKey: .locationId)
                }
            }

            struct Coil: Equatable, Decodable {
                let id: String
                let code: String

                private enum CodingKeys: String, CodingKey {
                    case id
                    case code
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    id = try container.decodeStringOrEmpty(forKey: .id)
                    code = try container.decodeStringOrEmpty(forKey: .code)
                }
            }

            struct StockingRun: Equatable, Decodable {
                let id: String
                let runDate: String

                private enum CodingKeys: String, CodingKey {
                    case id
                    case runDate
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    id = try container.decodeStringOrEmpty(forKey: .id)
                    runDate = try container.decodeStringOrEmpty(forKey: .runDate)
                }
            }

            var id: String { "\(coilItemId)-\(quantity)-\(plannedQuantity)" }

            let quantity: Int
            let plannedQuantity: Int
            let expiringQuantity: Int
            let stockingRun: StockingRun?
            let coilItemId: String
            let sku: Sku
            let machine: Machine
            let coil: Coil

            private enum CodingKeys: String, CodingKey {
                case quantity
                case plannedQuantity
                case expiringQuantity
                case stockingRun
                case coilItemId
                case sku
                case machine
                case coil
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let quantity = try container.decodeFlexibleIntIfPresent(forKey: .quantity) ?? 0
                let plannedQuantity = try container.decodeFlexibleIntIfPresent(forKey: .plannedQuantity) ?? 0
                let expiringQuantity = try container.decodeFlexibleIntIfPresent(forKey: .expiringQuantity) ?? quantity
                let stockingRun = try container.decodeIfPresent(StockingRun.self, forKey: .stockingRun)
                let sku = try container.decode(Sku.self, forKey: .sku)
                let machine = try container.decode(Machine.self, forKey: .machine)
                let coil = try container.decode(Coil.self, forKey: .coil)
                let coilItemId = try container.decodeIfPresent(String.self, forKey: .coilItemId) ?? "\(coil.id)-\(sku.id)"

                self.quantity = quantity
                self.plannedQuantity = plannedQuantity
                self.expiringQuantity = expiringQuantity
                self.stockingRun = stockingRun
                self.coilItemId = coilItemId
                self.sku = sku
                self.machine = machine
                self.coil = coil
            }
        }

        var id: String { expiryDate }

        let expiryDate: String
        let items: [Item]
        let runs: [RunOption]

        private enum CodingKeys: String, CodingKey {
            case expiryDate
            case items
            case runs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            expiryDate = try container.decodeStringOrEmpty(forKey: .expiryDate)
            items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
            runs = try container.decodeIfPresent([RunOption].self, forKey: .runs) ?? []
        }
    }

    let warningCount: Int
    let sections: [Section]

    private enum CodingKeys: String, CodingKey {
        case warningCount
        case sections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        warningCount = try container.decodeFlexibleIntIfPresent(forKey: .warningCount) ?? 0
        sections = try container.decodeIfPresent([Section].self, forKey: .sections) ?? []
    }
}
