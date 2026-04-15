// Copyright 2026 DIAMIR. All rights reserved.

import Foundation
import Security

/// Errors that can occur during authentication.
public enum AuthError: Error, LocalizedError {
    case invalidPrivateKey(String)
    case jwtSigningFailed(String)
    case tokenRequestFailed(Int, String)
    case invalidTokenResponse

    public var errorDescription: String? {
        switch self {
        case .invalidPrivateKey(let detail):
            return "Invalid private key: \(detail)"
        case .jwtSigningFailed(let detail):
            return "JWT signing failed: \(detail)"
        case .tokenRequestFailed(let code, let body):
            return "Token request failed with HTTP \(code): \(body)"
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

        var request = URLRequest(url: URL(string: credentials.tokenUri)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": jwt
        ]
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

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

        // Header
        let header = #"{"alg":"RS256","typ":"JWT"}"#
        let claims = """
        {
          "iss": "\(credentials.clientEmail)",
          "scope": "https://www.googleapis.com/auth/spreadsheets",
          "aud": "\(credentials.tokenUri)",
          "iat": \(now),
          "exp": \(expiry)
        }
        """

        let encodedHeader = base64URLEncode(header.data(using: .utf8)!)
        let encodedClaims = base64URLEncode(claims.data(using: .utf8)!)
        let signingInput = "\(encodedHeader).\(encodedClaims)"

        let signature = try signRS256(message: signingInput, pemKey: credentials.privateKey)
        return "\(signingInput).\(signature)"
    }

    private func signRS256(message: String, pemKey: String) throws -> String {
        let keyData = try PEMKeyDecoder.decodeRSAPrivateKeyData(from: pemKey)

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(
            keyData as CFData,
            [
                kSecAttrKeyType: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass: kSecAttrKeyClassPrivate
            ] as CFDictionary,
            &error
        ) else {
            let detail = error.map { CFErrorCopyDescription($0.takeRetainedValue()) as String } ?? "unknown"
            throw AuthError.invalidPrivateKey(detail)
        }

        let messageData = message.data(using: .utf8)!
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

enum PEMKeyDecoder {
    private static let rsaEncryptionOID = Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])

    static func decodeRSAPrivateKeyData(from pem: String) throws -> Data {
        let normalizedPEM = pem
            .replacingOccurrences(of: "\\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedPEM.contains("-----BEGIN ENCRYPTED PRIVATE KEY-----") {
            throw AuthError.invalidPrivateKey("Encrypted private keys are not supported.")
        }

        let decodedDER = try decodePEMBody(from: normalizedPEM)

        if normalizedPEM.contains("-----BEGIN RSA PRIVATE KEY-----") {
            return decodedDER
        }

        if normalizedPEM.contains("-----BEGIN PRIVATE KEY-----") {
            return try extractRSAPrivateKeyFromPKCS8(decodedDER)
        }

        throw AuthError.invalidPrivateKey(
            "Unsupported PEM header. Expected BEGIN PRIVATE KEY or BEGIN RSA PRIVATE KEY."
        )
    }

    private static func decodePEMBody(from pem: String) throws -> Data {
        let lines = pem
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let base64 = lines.joined()

        guard !base64.isEmpty else {
            throw AuthError.invalidPrivateKey("PEM body is empty.")
        }

        guard let data = Data(base64Encoded: base64) else {
            throw AuthError.invalidPrivateKey("Could not base64-decode PEM body.")
        }
        return data
    }

    private static func extractRSAPrivateKeyFromPKCS8(_ pkcs8Data: Data) throws -> Data {
        var topLevelReader = DERReader(data: pkcs8Data)
        let privateKeyInfo = try topLevelReader.readValue(tag: 0x30)

        guard topLevelReader.isAtEnd else {
            throw AuthError.invalidPrivateKey("Unexpected trailing data in PKCS#8 key.")
        }

        var privateKeyInfoReader = DERReader(data: privateKeyInfo)
        _ = try privateKeyInfoReader.readValue(tag: 0x02) // version

        let algorithmIdentifier = try privateKeyInfoReader.readValue(tag: 0x30)
        try validateAlgorithmIdentifier(algorithmIdentifier)

        let privateKeyOctets = try privateKeyInfoReader.readValue(tag: 0x04)
        try validateRSAPrivateKeyDER(privateKeyOctets)
        return privateKeyOctets
    }

    private static func validateAlgorithmIdentifier(_ data: Data) throws {
        var reader = DERReader(data: data)
        let oid = try reader.readValue(tag: 0x06)

        guard oid == rsaEncryptionOID else {
            throw AuthError.invalidPrivateKey("PKCS#8 key algorithm is not RSA.")
        }

        if let nullParameters = try reader.readOptionalValue(tag: 0x05), !nullParameters.isEmpty {
            throw AuthError.invalidPrivateKey("Invalid PKCS#8 RSA algorithm parameters.")
        }

        guard reader.isAtEnd else {
            throw AuthError.invalidPrivateKey("Unexpected data in PKCS#8 algorithm identifier.")
        }
    }

    private static func validateRSAPrivateKeyDER(_ data: Data) throws {
        var reader = DERReader(data: data)
        _ = try reader.readValue(tag: 0x30)

        guard reader.isAtEnd else {
            throw AuthError.invalidPrivateKey("Invalid RSA private key DER payload.")
        }
    }
}

private struct DERReader {
    let data: Data
    private(set) var offset: Int = 0

    var isAtEnd: Bool {
        offset == data.count
    }

    mutating func readValue(tag expectedTag: UInt8) throws -> Data {
        let (tag, value) = try readElement()
        guard tag == expectedTag else {
            throw AuthError.invalidPrivateKey(
                "Unexpected DER tag 0x\(hexString(tag)); expected 0x\(hexString(expectedTag))."
            )
        }
        return value
    }

    mutating func readOptionalValue(tag expectedTag: UInt8) throws -> Data? {
        guard offset < data.count else { return nil }
        guard data[offset] == expectedTag else { return nil }
        return try readValue(tag: expectedTag)
    }

    private mutating func readElement() throws -> (UInt8, Data) {
        guard offset < data.count else {
            throw AuthError.invalidPrivateKey("Unexpected end of DER data while reading tag.")
        }

        let tag = data[offset]
        offset += 1

        let length = try readLength()
        guard offset + length <= data.count else {
            throw AuthError.invalidPrivateKey("DER length exceeds available data.")
        }

        let value = data.subdata(in: offset..<(offset + length))
        offset += length
        return (tag, value)
    }

    private mutating func readLength() throws -> Int {
        guard offset < data.count else {
            throw AuthError.invalidPrivateKey("Unexpected end of DER data while reading length.")
        }

        let firstByte = data[offset]
        offset += 1

        if firstByte & 0x80 == 0 {
            return Int(firstByte)
        }

        let lengthByteCount = Int(firstByte & 0x7F)
        guard lengthByteCount > 0 else {
            throw AuthError.invalidPrivateKey("Indefinite DER lengths are not supported.")
        }

        guard lengthByteCount <= 4 else {
            throw AuthError.invalidPrivateKey("DER length uses too many bytes.")
        }

        guard offset + lengthByteCount <= data.count else {
            throw AuthError.invalidPrivateKey("Incomplete DER length bytes.")
        }

        var length = 0
        for _ in 0..<lengthByteCount {
            length = (length << 8) | Int(data[offset])
            offset += 1
        }
        return length
    }

    private func hexString(_ byte: UInt8) -> String {
        let hexDigits = Array("0123456789ABCDEF")
        let upper = Int(byte / 16)
        let lower = Int(byte % 16)
        return String(hexDigits[upper]) + String(hexDigits[lower])
    }
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
