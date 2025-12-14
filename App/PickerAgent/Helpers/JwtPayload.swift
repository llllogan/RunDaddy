//
//  JwtPayload.swift
//  PickAgent
//
//  Created by ChatGPT on 12/14/2025.
//

import Foundation

enum JwtPayload {
    static func companyId(from token: String) -> String? {
        guard let payloadObject = decodePayloadObject(from: token) else {
            return nil
        }

        guard let companyId = payloadObject["companyId"] else {
            return nil
        }

        return companyId as? String
    }

    private static func decodePayloadObject(from token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            return nil
        }

        let payloadSegment = String(parts[1])
        guard let payloadData = decodeBase64Url(payloadSegment) else {
            return nil
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: payloadData),
              let payloadObject = jsonObject as? [String: Any]
        else {
            return nil
        }

        return payloadObject
    }

    private static func decodeBase64Url(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = base64.count % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: 4 - padding)
        }

        return Data(base64Encoded: base64)
    }
}

