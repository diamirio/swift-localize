// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

/// Top-level orchestrator that coordinates authentication, Sheets API calls,
/// parsing, and reading/writing of localization artifacts.
///
/// Operations are performed sequentially per sheet tab.
public actor Localizer {
    private let config: LocalizerConfig
    private let sheetsClient: SheetsAPIClient

    public init(
        config: LocalizerConfig,
        sheetsClient: SheetsAPIClient = SheetsAPIClient()
    ) {
        self.config = config
        self.sheetsClient = sheetsClient
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
        for sheet in sheets {
            let token = try await authProvider.accessToken()
            try await pullTab(tabName: sheet.title, token: token)
        }
    }

    private func pullTab(tabName: String, token: String) async throws {
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

        let outputPath = (config.localizationPath as NSString).appendingPathComponent("\(tabName).xcstrings")

        // Load existing catalog for diff logging.
        let existingCatalog = try StringCatalogReader.read(from: outputPath)
        let hadExistingCatalog = (existingCatalog != nil)

        SyncLogger.logPullResult(
            tabName: tabName,
            newEntries: entries,
            oldCatalog: existingCatalog
        )

        try StringCatalogWriter.write(
            entries: entries,
            to: outputPath,
            sourceLanguage: config.sourceLanguage
        )

        if entries.isEmpty {
            if hadExistingCatalog {
                SyncLogger.info("[\(tabName)] No parsed strings; removed existing catalog file.")
            } else {
                SyncLogger.info("[\(tabName)] No parsed strings; no catalog file created.")
            }
        }
    }
}
