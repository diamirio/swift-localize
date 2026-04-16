// Copyright 2026 DIAMIR. All rights reserved.

import Foundation
import Security

/// Errors that can occur during authentication.
public enum AuthError: Error, LocalizedError {
    case invalidConfiguration(String)
    case invalidPrivateKey(String)
    case jwtSigningFailed(String)
    case tokenRequestFailed(Int, String)
    case invalidHTTPResponse
    case invalidTokenResponse

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let detail):
            return "Invalid authentication configuration: \(detail)"
        case .invalidPrivateKey(let detail):
            return "Invalid private key: \(detail)"
        case .jwtSigningFailed(let detail):
            return "JWT signing failed: \(detail)"
        case .tokenRequestFailed(let code, let body):
            return "Token request failed with HTTP \(code): \(body)"
        case .invalidHTTPResponse:
            return "Token endpoint did not return an HTTP response."
        case .invalidTokenResponse:
            return "Token response did not contain an access_token."
        }
    }
}

/// Authenticates with Google APIs using a Service Account and produces short-lived OAuth2 bearer tokens.
///
/// Tokens are cached and reused until they expire (Google issues 1-hour tokens).
public actor GoogleAuthProvider {
    private let credentials: ServiceAccountCredentials
    private var cachedToken: String?
    private var tokenExpiry: Date = .distantPast

    public init(credentials: ServiceAccountCredentials) {
        self.credentials = credentials
    }

    /// Returns a valid bearer token, fetching a new one if the cached token has expired.
    public func accessToken() async throws -> String {
        if let token = cachedToken, Date() < tokenExpiry {
            return token
        }
        let (token, expiresIn) = try await fetchToken()
        cachedToken = token
        // Subtract a 60-second buffer so we refresh before actual expiry.
        tokenExpiry = Date().addingTimeInterval(Double(expiresIn) - 60)
        return token
    }

    // MARK: - Private

    private func fetchToken() async throws -> (token: String, expiresIn: Int) {
        let jwt = try buildSignedJWT()

        guard let tokenURL = URL(string: credentials.tokenUri) else {
            throw AuthError.invalidConfiguration("Invalid token URI: \(credentials.tokenUri)")
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            URLQueryItem(name: "assertion", value: jwt),
        ]

        guard let body = bodyComponents.percentEncodedQuery?.data(using: .utf8) else {
            throw AuthError.invalidConfiguration("Could not encode token request body.")
        }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidHTTPResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.tokenRequestFailed(httpResponse.statusCode, body)
        }

        let json = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard !json.accessToken.isEmpty else {
            throw AuthError.invalidTokenResponse
        }
        return (json.accessToken, json.expiresIn)
    }

    private func buildSignedJWT() throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let expiry = now + 3600

        let header = JWTHeader(alg: "RS256", typ: "JWT")
        let claims = JWTClaims(
            iss: credentials.clientEmail,
            scope: "https://www.googleapis.com/auth/spreadsheets",
            aud: credentials.tokenUri,
            iat: now,
            exp: expiry
        )

        let encodedHeader = base64URLEncode(try JSONEncoder().encode(header))
        let encodedClaims = base64URLEncode(try JSONEncoder().encode(claims))
        let signingInput = "\(encodedHeader).\(encodedClaims)"

        let signature = try signRS256(message: signingInput, pemKey: credentials.privateKey)
        return "\(signingInput).\(signature)"
    }

    private func signRS256(message: String, pemKey: String) throws -> String {
        let privateKey = try PrivateKeyImporter.importRSAPrivateKey(from: pemKey)

        guard let messageData = message.data(using: .utf8) else {
            throw AuthError.jwtSigningFailed("Could not encode signing input.")
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            messageData as CFData,
            &error
        ) else {
            let detail = error.map { CFErrorCopyDescription($0.takeRetainedValue()) as String } ?? "unknown"
            throw AuthError.jwtSigningFailed(detail)
        }

        return base64URLEncode(signature as Data)
    }

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum PrivateKeyImporter {
    static func importRSAPrivateKey(from pem: String) throws -> SecKey {
        let normalizedPEM = pem
            .replacingOccurrences(of: "\\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedPEM.contains("-----BEGIN ENCRYPTED PRIVATE KEY-----") {
            throw AuthError.invalidPrivateKey("Encrypted private keys are not supported.")
        }

        guard normalizedPEM.contains("-----BEGIN PRIVATE KEY-----") else {
            throw AuthError.invalidPrivateKey("Unsupported PEM header. Expected BEGIN PRIVATE KEY.")
        }

        guard let pemData = normalizedPEM.data(using: .utf8) else {
            throw AuthError.invalidPrivateKey("Could not encode PEM as UTF-8.")
        }
        var format = SecExternalFormat.formatUnknown
        var itemType = SecExternalItemType.itemTypeUnknown
        var importedItems: CFArray?

        let status = SecItemImport(
            pemData as CFData,
            nil,
            &format,
            &itemType,
            [],
            nil,
            nil,
            &importedItems
        )

        guard status == errSecSuccess else {
            throw AuthError.invalidPrivateKey("Could not import private key: \(errorMessage(for: status))")
        }

        guard let importedItems else {
            throw AuthError.invalidPrivateKey("No key material found in PEM.")
        }

        let itemCount = CFArrayGetCount(importedItems)
        for index in 0..<itemCount {
            let rawItem = CFArrayGetValueAtIndex(importedItems, index)
            let item = unsafeBitCast(rawItem, to: AnyObject.self)
            guard CFGetTypeID(item) == SecKeyGetTypeID() else {
                continue
            }

            let key = unsafeBitCast(rawItem, to: SecKey.self)
            try validateIsRSA(key: key)
            return key
        }

        throw AuthError.invalidPrivateKey("Imported PEM did not contain a private key.")
    }

    private static func validateIsRSA(key: SecKey) throws {
        guard let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
              let keyType = attributes[kSecAttrKeyType] else {
            throw AuthError.invalidPrivateKey("Could not inspect imported key attributes.")
        }

        guard CFEqual(keyType as CFTypeRef, kSecAttrKeyTypeRSA) else {
            throw AuthError.invalidPrivateKey("Private key algorithm is not RSA.")
        }
    }

    private static func errorMessage(for status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "OSStatus \(status)"
    }
}

private struct JWTHeader: Encodable {
    let alg: String
    let typ: String
}

private struct JWTClaims: Encodable {
    let iss: String
    let scope: String
    let aud: String
    let iat: Int
    let exp: Int
}

// MARK: - Token response model

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}
