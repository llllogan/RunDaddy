//
//  InviteCodesService.swift
//  PickAgent
//
//  Created by ChatGPT on 11/8/2025.
//

import Foundation
import CoreImage

protocol InviteCodesServicing {
    func generateInviteCode(companyId: String, role: UserRole, credentials: AuthCredentials) async throws -> InviteCode
    func useInviteCode(_ code: String, credentials: AuthCredentials) async throws -> JoinCompanyResult
    func fetchInviteCodes(for companyId: String, credentials: AuthCredentials) async throws -> [InviteCode]
    func leaveCompany(companyId: String, credentials: AuthCredentials) async throws -> LeaveCompanyResult
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
    let company: InviteCompanyInfo?
    let creator: CreatorInfo?
    let usedByUser: UsedByUserInfo?
    
    struct InviteCompanyInfo: Equatable, Codable {
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
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue("H", forKey: "inputCorrectionLevel")
        
        guard let qrImage = filter?.outputImage else { return nil }
        
        // Scale up the QR code to make it visible
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        return qrImage.transformed(by: transform)
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
    let company: MembershipCompanyInfo?
    
    struct MembershipCompanyInfo: Equatable, Codable {
        let name: String
        let location: String?
        let timeZone: String?
        let showColdChest: Bool?
        let showChocolateBoxes: Bool?
    }
    
    var roleDisplay: String {
        role.rawValue.capitalized
    }
}

struct JoinCompanyResult {
    let membership: Membership
    let credentials: AuthCredentials
}

struct LeaveCompanyResult {
    let membership: Membership?
    let credentials: AuthCredentials
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
    
    static var inviteAssignableRoles: [UserRole] {
        [.owner, .admin, .picker]
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
        url.appendPathComponent("companies")
        url.appendPathComponent(companyId)
        url.appendPathComponent("invite-codes")

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

        if !(200..<300).contains(httpResponse.statusCode) {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw InviteCodesServiceError.insufficientPermissions
            }
            if httpResponse.statusCode == 409 {
                let reason = InviteCodesService.parseErrorMessage(from: data)
                throw InviteCodesServiceError.planLimitReached(reason: reason)
            }
            throw InviteCodesServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode(InviteCodeResponse.self, from: data)
        return payload.toInviteCode()
    }

    func useInviteCode(_ code: String, credentials: AuthCredentials) async throws -> JoinCompanyResult {
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

        if !(200..<300).contains(httpResponse.statusCode) {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 400 {
                throw InviteCodesServiceError.invalidOrExpiredCode
            }
            if httpResponse.statusCode == 409 {
                let reason = InviteCodesService.parseErrorMessage(from: data)
                throw InviteCodesServiceError.planLimitReached(reason: reason)
            }
            throw InviteCodesServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode(SessionResponse.self, from: data)
        
        guard let membershipResponse = payload.membership else {
            throw InviteCodesServiceError.invalidResponse
        }
        
        return JoinCompanyResult(
            membership: membershipResponse.toMembership(),
            credentials: payload.buildCredentials()
        )
    }

    func fetchInviteCodes(for companyId: String, credentials: AuthCredentials) async throws -> [InviteCode] {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("companies")
        url.appendPathComponent(companyId)
        url.appendPathComponent("invite-codes")

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

    func leaveCompany(companyId: String, credentials: AuthCredentials) async throws -> LeaveCompanyResult {
        // Use the new /companies/{companyId}/leave endpoint
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("companies")
        url.appendPathComponent(companyId)
        url.appendPathComponent("leave")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        
        print("🔄 Leaving company using endpoint: POST \(url.absoluteString)")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InviteCodesServiceError.invalidResponse
        }
        
        print("📊 Response status code: \(httpResponse.statusCode)")
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            } else if httpResponse.statusCode == 403 {
                throw InviteCodesServiceError.insufficientPermissions
            } else if httpResponse.statusCode == 404 {
                throw InviteCodesServiceError.companyNotFound
            } else {
                print("❌ Server error \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 Response body: \(responseString)")
                }
                throw InviteCodesServiceError.serverError(code: httpResponse.statusCode)
            }
        }
        
        print("✅ Successfully left company")
        
        let payload = try decoder.decode(SessionResponse.self, from: data)
        return LeaveCompanyResult(
            membership: payload.membership?.toMembership(),
            credentials: payload.buildCredentials()
        )
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
    let company: InviteCode.InviteCompanyInfo?
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
            company: company.map { InviteCode.InviteCompanyInfo(name: $0.name) },
            creator: creator.map { InviteCode.CreatorInfo(firstName: $0.firstName, lastName: $0.lastName) },
            usedByUser: usedByUser.map { InviteCode.UsedByUserInfo(firstName: $0.firstName, lastName: $0.lastName) }
        )
    }
}

private struct SessionResponse: Decodable {
    struct SessionUser: Decodable {
        let id: String
    }
    
    struct SessionMembershipCompany: Decodable {
        let id: String?
        let name: String
        let location: String?
        let timeZone: String?
        let showColdChest: Bool?
        let showChocolateBoxes: Bool?
    }
    
    struct MembershipResponse: Decodable {
        let id: String
        let userId: String
        let companyId: String
        let role: String
        let company: SessionMembershipCompany?
        
        func toMembership() -> Membership {
            Membership(
                id: id,
                userId: userId,
                companyId: companyId,
                role: UserRole(rawValue: role) ?? .picker,
                company: company.map {
                    Membership.MembershipCompanyInfo(
                        name: $0.name,
                        location: $0.location,
                        timeZone: $0.timeZone,
                        showColdChest: $0.showColdChest,
                        showChocolateBoxes: $0.showChocolateBoxes
                    )
                }
            )
        }
    }
    
    let user: SessionUser
    let company: SessionMembershipCompany?
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: Date?
    let refreshTokenExpiresAt: Date?
    let membership: MembershipResponse?
    
    func buildCredentials(currentDate: Date = .now) -> AuthCredentials {
        let expirationDate = accessTokenExpiresAt ?? currentDate.addingTimeInterval(3600)
        return AuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userID: user.id,
            expiresAt: expirationDate
        )
    }
}

enum InviteCodesServiceError: LocalizedError {
    case invalidResponse
    case serverError(code: Int)
    case insufficientPermissions
    case invalidOrExpiredCode
    case companyNotFound
    case planLimitReached(reason: String?)

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
        case .companyNotFound:
            return "Company not found or you're not a member."
        case let .planLimitReached(reason):
            return reason ?? "Your plan is at capacity for this role."
        }
    }
}

private extension InviteCodesService {
    static func parseErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else { return nil }

        if let detail = json["detail"] as? String {
            return detail
        }
        if let error = json["error"] as? String {
            return error
        }
        return nil
    }
}
