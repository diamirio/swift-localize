// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

/// Top-level orchestrator that coordinates authentication, Sheets API calls,
/// parsing, and reading/writing of localization artifacts.
///
/// Operations are performed sequentially per sheet tab.
public actor Localizer {
    private let config: LocalizerConfig
    private let sheetsClient: SheetsAPIClient
    private let xcodeLocalizationService: XcodeLocalizationService

    public init(
        config: LocalizerConfig,
        sheetsClient: SheetsAPIClient = SheetsAPIClient(),
        xcodeLocalizationService: XcodeLocalizationService = XcodeLocalizationService()
    ) {
        self.config = config
        self.sheetsClient = sheetsClient
        self.xcodeLocalizationService = xcodeLocalizationService
    }

    /// Runs the pull sync.
    public func run() async throws {
        SyncLogger.info("Starting pull — spreadsheet: \(config.spreadsheetId)")

        let credentials = try ServiceAccountCredentials.load(from: config.credentialsPath)
        let authProvider = GoogleAuthProvider(credentials: credentials)
        let token = try await authProvider.accessToken()

        let sheets = try await sheetsClient.getSheetMetadata(
            spreadsheetId: config.spreadsheetId,
            token: token
        )

        SyncLogger.info("Found \(sheets.count) tab(s): \(sheets.map(\.title).joined(separator: ", "))")

        try await pullAll(sheets: sheets, authProvider: authProvider)

        SyncLogger.info("Done.")
    }

    // MARK: - Pull (Sheets → Catalog)

    private func pullAll(sheets: [SheetMetadata], authProvider: GoogleAuthProvider) async throws {
        let xcodeLocalization = resolveXcodeLocalizationMode()
        if xcodeLocalization.isEnabled {
            SyncLogger.info("Exporting XLIFF from Xcode project...")
            try xcodeLocalizationService.exportLocalizations(
                config: config,
                localizationPath: config.outputDirectory
            )
        } else if let reason = xcodeLocalization.disabledReason {
            SyncLogger.warning("Xcode export/import disabled: \(reason). Falling back to local output artifacts.")
        }

        var translationsByKey: [String: [String: String]] = [:]

        for sheet in sheets {
            let token = try await authProvider.accessToken()
            let entries = try await pullTab(tabName: sheet.title, token: token)
            merge(entries: entries, tabName: sheet.title, into: &translationsByKey)
        }

        let updateResults = try XLIFFService.applyTranslations(
            translationsByKey,
            sourceLanguage: config.sourceLanguage,
            in: config.outputDirectory
        )

        let updatedUnits = updateResults.reduce(0) { $0 + $1.updatedUnitCount }
        SyncLogger.info(
            "Applied sheet translations to XLIFF (\(updatedUnits) trans-unit update(s) across \(updateResults.count) file(s))"
        )

        if xcodeLocalization.isEnabled {
            SyncLogger.info("Importing XLIFF back into Xcode project...")
            try xcodeLocalizationService.importLocalizations(
                config: config,
                localizationPath: config.outputDirectory
            )
        }
    }

    private func merge(entries: [ParsedEntry], tabName: String, into map: inout [String: [String: String]]) {
        for entry in entries {
            var existing = map[entry.key] ?? [:]
            for (language, value) in entry.translations {
                if let current = existing[language], current != value {
                    SyncLogger.warning(
                        "[\(tabName)] Duplicate key '\(entry.key)' has conflicting \(language) values across sheets; latest value wins."
                    )
                }
                existing[language] = value
            }
            map[entry.key] = existing
        }
    }

    private func pullTab(tabName: String, token: String) async throws -> [ParsedEntry] {
        SyncLogger.info("[\(tabName)] Fetching values...")

        let rows = try await sheetsClient.getSheetValues(
            spreadsheetId: config.spreadsheetId,
            sheetName: tabName,
            token: token
        )

        let entries = SheetParser.parse(rows: rows)

        let parsedLanguages = Set(entries.flatMap { $0.translations.keys }).sorted()
        SyncLogger.info(
            "[\(tabName)] Parsed language keys from rows: \(parsedLanguages.isEmpty ? "none" : parsedLanguages.joined(separator: ", "))"
        )

        // Load existing catalog for diff logging.
        let catalogPath = outputPath(for: tabName)
        let existingCatalog = try StringCatalogReader.read(from: catalogPath)
        let hadExistingCatalog = (existingCatalog != nil)

        SyncLogger.logPullResult(
            tabName: tabName,
            newEntries: entries,
            oldCatalog: existingCatalog
        )

        try StringCatalogWriter.write(
            entries: entries,
            tabName: tabName,
            outputDirectory: config.outputDirectory,
            sourceLanguage: config.sourceLanguage
        )

        if entries.isEmpty {
            if hadExistingCatalog {
                SyncLogger.info("[\(tabName)] No parsed strings; removed existing catalog file.")
            } else {
                SyncLogger.info("[\(tabName)] No parsed strings; no catalog file created.")
            }
        }

        return entries
    }

    // MARK: - Helpers

    private func outputPath(for tabName: String) -> String {
        (config.outputDirectory as NSString).appendingPathComponent("\(tabName).xcstrings")
    }

    private func resolveXcodeLocalizationMode() -> XcodeLocalizationMode {
        let projectPath = normalized(config.xcodeProjectPath)
        let workspacePath = normalized(config.xcodeWorkspacePath)
        let scheme = normalized(config.xcodeScheme)

        if projectPath == nil && workspacePath == nil {
            return XcodeLocalizationMode(isEnabled: false, disabledReason: "no Xcode project/workspace configured")
        }

        if projectPath != nil && workspacePath != nil {
            return XcodeLocalizationMode(
                isEnabled: false,
                disabledReason: "both xcodeProjectPath and xcodeWorkspacePath are set"
            )
        }

        if let projectPath {
            guard FileManager.default.fileExists(atPath: projectPath) else {
                return XcodeLocalizationMode(
                    isEnabled: false,
                    disabledReason: "xcodeProjectPath does not exist at '\(projectPath)'"
                )
            }
            return XcodeLocalizationMode(isEnabled: true, disabledReason: nil)
        }

        guard let workspacePath else {
            return XcodeLocalizationMode(isEnabled: false, disabledReason: "workspace path is missing")
        }

        guard FileManager.default.fileExists(atPath: workspacePath) else {
            return XcodeLocalizationMode(
                isEnabled: false,
                disabledReason: "xcodeWorkspacePath does not exist at '\(workspacePath)'"
            )
        }

        guard scheme != nil else {
            return XcodeLocalizationMode(
                isEnabled: false,
                disabledReason: "xcodeScheme is required when xcodeWorkspacePath is set"
            )
        }

        return XcodeLocalizationMode(isEnabled: true, disabledReason: nil)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct XcodeLocalizationMode {
    let isEnabled: Bool
    let disabledReason: String?
}
