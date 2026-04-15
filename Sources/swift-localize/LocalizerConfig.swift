// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

/// Configuration for the Localizer, loadable from a JSON file.
public struct LocalizerConfig: Codable, Sendable {
    /// Path to the Google service account JSON key file.
    public let credentialsPath: String

    /// The Google Sheets spreadsheet ID (from the URL).
    public let spreadsheetId: String

    /// Directory used as `-localizationPath` for XLIFF export/import and
    /// where per-tab `.xcstrings` snapshots are read/written.
    public let outputDirectory: String

    /// The BCP-47 language code to use as `sourceLanguage` in all catalogs.
    public let sourceLanguage: String

    /// Path to the `.xcodeproj` used for `xcodebuild -exportLocalizations/-importLocalizations`.
    /// Exactly one of `xcodeProjectPath` or `xcodeWorkspacePath` must be set.
    public let xcodeProjectPath: String?

    /// Path to the `.xcworkspace` used for `xcodebuild -exportLocalizations/-importLocalizations`.
    /// Exactly one of `xcodeProjectPath` or `xcodeWorkspacePath` must be set.
    public let xcodeWorkspacePath: String?

    /// Required when `xcodeWorkspacePath` is set.
    public let xcodeScheme: String?

    public init(
        credentialsPath: String,
        spreadsheetId: String,
        outputDirectory: String,
        sourceLanguage: String = "de",
        xcodeProjectPath: String? = nil,
        xcodeWorkspacePath: String? = nil,
        xcodeScheme: String? = nil
    ) {
        self.credentialsPath = credentialsPath
        self.spreadsheetId = spreadsheetId
        self.outputDirectory = outputDirectory
        self.sourceLanguage = sourceLanguage
        self.xcodeProjectPath = xcodeProjectPath
        self.xcodeWorkspacePath = xcodeWorkspacePath
        self.xcodeScheme = xcodeScheme
    }

    /// Loads a `LocalizerConfig` from a JSON file at the given path.
    public static func load(from filePath: String) throws -> LocalizerConfig {
        let url = URL(fileURLWithPath: filePath)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LocalizerConfig.self, from: data)
    }
}
