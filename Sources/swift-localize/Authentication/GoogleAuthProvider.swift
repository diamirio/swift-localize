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
    /// Imports an RSA private key from a PEM-encoded PKCS#8 string.
    ///
    /// Uses only APIs available on both macOS and iOS (`SecKeyCreateWithData`),
    /// avoiding the macOS-only `SecItemImport`.
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

        // Strip PEM armor and base64-decode to get DER bytes (PKCS#8 format).
        let base64 = normalizedPEM
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            .joined()

        guard let pkcs8DER = Data(base64Encoded: base64) else {
            throw AuthError.invalidPrivateKey("Could not base64-decode PEM body.")
        }

        // Strip the PKCS#8 ASN.1 outer wrapper to obtain the inner PKCS#1 RSA key bytes.
        // SecKeyCreateWithData requires the raw PKCS#1 DER for RSA private keys.
        let pkcs1DER = try stripPKCS8Header(from: pkcs8DER)

        var error: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]

        guard let key = SecKeyCreateWithData(pkcs1DER as CFData, attributes as CFDictionary, &error) else {
            let detail = error.map { CFErrorCopyDescription($0.takeRetainedValue()) as String } ?? "unknown"
            throw AuthError.invalidPrivateKey("SecKeyCreateWithData failed: \(detail)")
        }

        return key
    }

    // MARK: - PKCS#8 ASN.1 unwrapping

    /// Strips the PKCS#8 outer ASN.1 wrapper from DER-encoded data and returns
    /// the inner PKCS#1 `RSAPrivateKey` bytes.
    ///
    /// PKCS#8 structure (simplified):
    /// ```
    /// SEQUENCE {
    ///   INTEGER 0                          -- version
    ///   SEQUENCE { OID rsaEncryption, NULL } -- algorithm identifier
    ///   OCTET STRING {                     -- privateKey
    ///     <PKCS#1 RSAPrivateKey DER>
    ///   }
    /// }
    /// ```
    private static func stripPKCS8Header(from der: Data) throws -> Data {
        var index = der.startIndex

        // Outer SEQUENCE
        try expect(tag: 0x30, in: der, at: &index)
        try skipLength(in: der, at: &index)

        // version INTEGER (0)
        try expect(tag: 0x02, in: der, at: &index)
        let versionLen = try readLength(in: der, at: &index)
        index = der.index(index, offsetBy: versionLen)

        // Algorithm identifier SEQUENCE — skip entirely
        try expect(tag: 0x30, in: der, at: &index)
        let algIdLen = try readLength(in: der, at: &index)
        index = der.index(index, offsetBy: algIdLen)

        // privateKey OCTET STRING — the payload is the PKCS#1 key
        try expect(tag: 0x04, in: der, at: &index)
        let keyLen = try readLength(in: der, at: &index)

        guard der.distance(from: index, to: der.endIndex) >= keyLen else {
            throw AuthError.invalidPrivateKey("PKCS#8 OCTET STRING length exceeds available data.")
        }

        return der[index ..< der.index(index, offsetBy: keyLen)]
    }

    /// Asserts the next byte equals `tag` and advances the index past it.
    private static func expect(tag: UInt8, in data: Data, at index: inout Data.Index) throws {
        guard index < data.endIndex, data[index] == tag else {
            let found = index < data.endIndex ? String(data[index], radix: 16) : "end-of-data"
            throw AuthError.invalidPrivateKey(
                "ASN.1 parse error: expected tag 0x\(String(tag, radix: 16)), found 0x\(found)."
            )
        }
        index = data.index(after: index)
    }

    /// Reads a DER-encoded length and advances the index past the length bytes.
    private static func readLength(in data: Data, at index: inout Data.Index) throws -> Int {
        guard index < data.endIndex else {
            throw AuthError.invalidPrivateKey("ASN.1 parse error: unexpected end of data while reading length.")
        }
        let first = data[index]
        index = data.index(after: index)

        if first & 0x80 == 0 {
            // Short form: length is the byte itself.
            return Int(first)
        }

        // Long form: lower 7 bits give the number of subsequent length bytes.
        let numBytes = Int(first & 0x7F)
        guard numBytes > 0, numBytes <= 4 else {
            throw AuthError.invalidPrivateKey("ASN.1 parse error: unsupported length encoding (numBytes=\(numBytes)).")
        }
        guard data.distance(from: index, to: data.endIndex) >= numBytes else {
            throw AuthError.invalidPrivateKey("ASN.1 parse error: not enough bytes for length encoding.")
        }

        var length = 0
        for _ in 0 ..< numBytes {
            length = (length << 8) | Int(data[index])
            index = data.index(after: index)
        }
        return length
    }

    /// Reads and discards a DER length field (convenience wrapper over `readLength`).
    private static func skipLength(in data: Data, at index: inout Data.Index) throws {
        _ = try readLength(in: data, at: &index)
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
