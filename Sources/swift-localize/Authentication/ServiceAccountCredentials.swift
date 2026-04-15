// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

/// Represents the fields in a Google Service Account JSON key file.
public struct ServiceAccountCredentials: Codable, Sendable {
    public let type: String
    public let projectId: String
    public let privateKeyId: String
    /// PEM-encoded RSA private key.
    public let privateKey: String
    public let clientEmail: String
    public let clientId: String
    public let authUri: String
    public let tokenUri: String

    enum CodingKeys: String, CodingKey {
        case type
        case projectId = "project_id"
        case privateKeyId = "private_key_id"
        case privateKey = "private_key"
        case clientEmail = "client_email"
        case clientId = "client_id"
        case authUri = "auth_uri"
        case tokenUri = "token_uri"
    }

    /// Loads credentials from a JSON file at the given path.
    public static func load(from filePath: String) throws -> ServiceAccountCredentials {
        let url = URL(fileURLWithPath: filePath)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ServiceAccountCredentials.self, from: data)
    }
}
