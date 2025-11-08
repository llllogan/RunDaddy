//
//  InviteCodesService.swift
//  PickAgent
//
//  Created by ChatGPT on 11/8/2025.
//

import Foundation
import CoreImage.CIQRCodeGenerator

protocol InviteCodesServicing {
    func generateInviteCode(companyId: String, role: UserRole, credentials: AuthCredentials) async throws -> InviteCode
    func useInviteCode(_ code: String, credentials: AuthCredentials) async throws -> Membership
    func fetchInviteCodes(for companyId: String, credentials: AuthCredentials) async throws -> [InviteCode]
}

struct InviteCode: Identifiable, Equatable, Codable {
    let id: String
    let code: String
    let companyId: String
    let role: UserRole
    let createdBy: String
    let expiresAt: Date
    let usedBy: String?
    let usedAt: Date?
    let createdAt: Date
    let company: CompanyInfo?
    let creator: CreatorInfo?
    let usedByUser: UsedByUserInfo?
    
    struct CompanyInfo: Equatable, Codable {
        let name: String
    }
    
    struct CreatorInfo: Equatable, Codable {
        let firstName: String?
        let lastName: String?
    }
    
    struct UsedByUserInfo: Equatable, Codable {
        let firstName: String?
        let lastName: String?
    }
    
    var qrCodeImage: CIImage? {
        let data = Data(code.utf8)
        return CIImage(qrCode: data)
    }
    
    var isExpired: Bool {
        Date() > expiresAt
    }
    
    var isUsed: Bool {
        usedBy != nil
    }
    
    var roleDisplay: String {
        role.rawValue.capitalized
    }
    
    var expiresAtDisplay: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: expiresAt)
    }
}

struct Membership: Identifiable, Equatable, Codable {
    let id: String
    let userId: String
    let companyId: String
    let role: UserRole
    let company: CompanyInfo?
    
    struct CompanyInfo: Equatable, Codable {
        let name: String
    }
    
    var roleDisplay: String {
        role.rawValue.capitalized
    }
}

enum UserRole: String, CaseIterable, Equatable, Codable {
    case admin = "ADMIN"
    case owner = "OWNER"
    case picker = "PICKER"
    
    var displayName: String {
        switch self {
        case .admin:
            return "Admin"
        case .owner:
            return "Owner"
        case .picker:
            return "Picker"
        }
    }
}

final class InviteCodesService: InviteCodesServicing {
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func generateInviteCode(companyId: String, role: UserRole, credentials: AuthCredentials) async throws -> InviteCode {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("invite-codes")
        url.appendPathComponent("generate")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "companyId": companyId,
            "role": role.rawValue
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InviteCodesServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw InviteCodesServiceError.insufficientPermissions
            }
            throw InviteCodesServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode(InviteCodeResponse.self, from: data)
        return payload.toInviteCode()
    }

    func useInviteCode(_ code: String, credentials: AuthCredentials) async throws -> Membership {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("invite-codes")
        url.appendPathComponent("use")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["code": code]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InviteCodesServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 400 {
                throw InviteCodesServiceError.invalidOrExpiredCode
            }
            throw InviteCodesServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode(UseInviteCodeResponse.self, from: data)
        return payload.membership.toMembership()
    }

    func fetchInviteCodes(for companyId: String, credentials: AuthCredentials) async throws -> [InviteCode] {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("invite-codes")
        url.appendPathComponent("company")
        url.appendPathComponent(companyId)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InviteCodesServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw InviteCodesServiceError.insufficientPermissions
            }
            throw InviteCodesServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode([InviteCodeResponse].self, from: data)
        return payload.map { $0.toInviteCode() }
    }
}

private struct InviteCodeResponse: Decodable {
    let id: String
    let code: String
    let companyId: String
    let role: String
    let createdBy: String
    let expiresAt: Date
    let usedBy: String?
    let usedAt: Date?
    let createdAt: Date
    let company: InviteCode.CompanyInfo?
    let creator: CreatorInfoResponse?
    let usedByUser: UsedByUserInfoResponse?
    
    struct CreatorInfoResponse: Decodable {
        let firstName: String?
        let lastName: String?
    }
    
    struct UsedByUserInfoResponse: Decodable {
        let firstName: String?
        let lastName: String?
    }

    func toInviteCode() -> InviteCode {
        InviteCode(
            id: id,
            code: code,
            companyId: companyId,
            role: UserRole(rawValue: role) ?? .picker,
            createdBy: createdBy,
            expiresAt: expiresAt,
            usedBy: usedBy,
            usedAt: usedAt,
            createdAt: createdAt,
            company: company,
            creator: creator.map { InviteCode.CreatorInfo(firstName: $0.firstName, lastName: $0.lastName) },
            usedByUser: usedByUser.map { InviteCode.UsedByUserInfo(firstName: $0.firstName, lastName: $0.lastName) }
        )
    }
}

private struct UseInviteCodeResponse: Decodable {
    let message: String
    let membership: MembershipResponse
    
    struct MembershipResponse: Decodable {
        let id: String
        let userId: String
        let companyId: String
        let role: String
        let company: Membership.CompanyInfo?
        
        func toMembership() -> Membership {
            Membership(
                id: id,
                userId: userId,
                companyId: companyId,
                role: UserRole(rawValue: role) ?? .picker,
                company: company
            )
        }
    }
}

enum InviteCodesServiceError: LocalizedError {
    case invalidResponse
    case serverError(code: Int)
    case insufficientPermissions
    case invalidOrExpiredCode

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "We couldn't connect to RunDaddy right now. Please try again."
        case let .serverError(code):
            return "Invite code operation failed with an unexpected error (code \(code))."
        case .insufficientPermissions:
            return "You don't have permission to manage invite codes for this company."
        case .invalidOrExpiredCode:
            return "This invite code is invalid or has expired."
        }
    }
}