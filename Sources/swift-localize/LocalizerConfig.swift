// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

/// Configuration for the Localizer, loadable from a JSON file.
public struct LocalizerConfig: Codable, Sendable {
    /// Path to the Google service account JSON key file.
    public let credentialsPath: String

    /// The Google Sheets spreadsheet ID (from the URL).
    public let spreadsheetId: String

    /// Directory where `.xcstrings` files are written.
    /// Each sheet tab is written as `<localizationPath>/<tabName>.xcstrings`.
    public let localizationPath: String

    /// The BCP-47 language code to use as `sourceLanguage` in all catalogs.
    public let sourceLanguage: String

    /// Optional allow-list of sheet tabs to import. When `nil` or empty, all tabs are processed.
    public let tabs: [String]?

    /// Optional override for the identifier column header name in the sheet.
    /// Defaults to `"Identifier iOS"` when not specified.
    public let identifierColumn: String?

    /// The effective identifier column header, with default applied.
    public var effectiveIdentifierColumn: String {
        let trimmed = identifierColumn?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? "Identifier iOS" : trimmed
    }

    public init(
        credentialsPath: String,
        spreadsheetId: String,
        localizationPath: String,
        sourceLanguage: String = "de",
        tabs: [String]? = nil,
        identifierColumn: String? = nil
    ) {
        self.credentialsPath = credentialsPath
        self.spreadsheetId = spreadsheetId
        self.localizationPath = localizationPath
        self.sourceLanguage = sourceLanguage
        self.tabs = tabs
        self.identifierColumn = identifierColumn
    }

    /// Loads a `LocalizerConfig` from a JSON file at the given path.
    ///
    /// All relative paths in the config (e.g. `credentialsPath`, `localizationPath`)
    /// are resolved relative to the config file's own directory,
    /// so the CLI can be invoked from any working directory.
    public static func load(from filePath: String) throws -> LocalizerConfig {
        let url = URL(fileURLWithPath: filePath).standardizedFileURL
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(LocalizerConfig.self, from: data)
        let baseURL = url.deletingLastPathComponent()
        return config.rebased(relativeTo: baseURL)
    }

    /// Returns a copy of the config with all path fields resolved relative to `base`.
    /// Paths that are already absolute are left unchanged.
    func rebased(relativeTo base: URL) -> LocalizerConfig {
        LocalizerConfig(
            credentialsPath: Self.resolve(credentialsPath, relativeTo: base),
            spreadsheetId: spreadsheetId,
            localizationPath: Self.resolve(localizationPath, relativeTo: base),
            sourceLanguage: sourceLanguage,
            tabs: tabs,
            identifierColumn: identifierColumn
        )
    }

    private static func resolve(_ path: String, relativeTo base: URL) -> String {
        guard !path.hasPrefix("/") else { return path }
        return URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL.path
    }
}
