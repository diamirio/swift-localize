// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

/// Errors from the Google Sheets API client.
public enum SheetsAPIError: Error, LocalizedError {
    case httpError(Int, String)
    case unexpectedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            return "Sheets API HTTP \(code): \(body)"
        case .unexpectedResponse(let detail):
            return "Unexpected Sheets API response: \(detail)"
        }
    }
}

/// Metadata for a single sheet (tab) within a spreadsheet.
public struct SheetMetadata: Sendable {
    public let sheetId: Int
    public let title: String
}

/// URLSession-based Google Sheets v4 API client.
public struct SheetsAPIClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Spreadsheet metadata

    /// Returns metadata (title + sheetId) for every tab in the spreadsheet.
    public func getSheetMetadata(spreadsheetId: String, token: String) async throws -> [SheetMetadata] {
        let url = sheetsBaseURL(spreadsheetId: spreadsheetId, path: "")
            .appending(queryItems: [URLQueryItem(name: "fields", value: "sheets.properties")])
        let data = try await get(url: url, token: token)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sheets = json["sheets"] as? [[String: Any]]
        else {
            throw SheetsAPIError.unexpectedResponse("Could not parse spreadsheet metadata.")
        }

        return sheets.compactMap { sheet -> SheetMetadata? in
            guard
                let props = sheet["properties"] as? [String: Any],
                let title = props["title"] as? String,
                let sheetId = props["sheetId"] as? Int
            else { return nil }
            return SheetMetadata(sheetId: sheetId, title: title)
        }
    }

    // MARK: - Reading values

    /// Returns all values for a named sheet tab as a 2D array of strings.
    /// Rows may have different lengths; missing trailing cells are not present.
    public func getSheetValues(
        spreadsheetId: String,
        sheetName: String,
        token: String
    ) async throws -> [[String]] {
        let encodedName = sheetName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sheetName
        let url = sheetsBaseURL(spreadsheetId: spreadsheetId, path: "/values/\(encodedName)")
            .appending(queryItems: [URLQueryItem(name: "valueRenderOption", value: "FORMATTED_VALUE")])
        let data = try await get(url: url, token: token)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw SheetsAPIError.unexpectedResponse("Could not parse values response.")
        }

        // The API omits the "values" key entirely if the sheet is empty.
        let rawValues = json["values"] as? [[Any]] ?? []
        return rawValues.map { row in
            row.map { cell in
                (cell as? String) ?? "\(cell)"
            }
        }
    }

    // MARK: - Helpers

    private func sheetsBaseURL(spreadsheetId: String, path: String) -> URL {
        URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)\(path)")!
    }

    private func get(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SheetsAPIError.unexpectedResponse("Response was not an HTTPURLResponse.")
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SheetsAPIError.httpError(httpResponse.statusCode, body)
        }
        return data
    }

}

// MARK: - URL helpers (macOS 13 backport)

private extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + queryItems
        return components.url!
    }
}
