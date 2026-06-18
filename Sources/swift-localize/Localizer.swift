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

        let allSheets = try await sheetsClient.getSheetMetadata(
            spreadsheetId: config.spreadsheetId,
            token: token
        )

        let filteredSheets = filterTabs(allSheets)

        SyncLogger.info("Found \(allSheets.count) tab(s): \(allSheets.map(\.title).joined(separator: ", "))")
        if filteredSheets.count != allSheets.count {
            let skipped = Set(allSheets.map(\.title)).subtracting(filteredSheets.map(\.title)).sorted()
            SyncLogger.info("Filtered to \(filteredSheets.count) tab(s); skipping: \(skipped.joined(separator: ", "))")
        }

        let summary = try await pullAll(sheets: filteredSheets, authProvider: authProvider)

        SyncLogger.info(
            "Done. Tabs synced: \(summary.tabs), added: \(summary.added), removed: \(summary.removed), updated: \(summary.updated)."
        )
    }

    // MARK: - Tab filtering

    private func filterTabs(_ sheets: [SheetMetadata]) -> [SheetMetadata] {
        guard let requested = config.tabs, !requested.isEmpty else {
            return sheets
        }
        let requestedSet = Set(requested)
        let available = Set(sheets.map(\.title))
        let missing = requestedSet.subtracting(available).sorted()
        if !missing.isEmpty {
            SyncLogger.warning("Requested tab(s) not found in spreadsheet: \(missing.joined(separator: ", "))")
        }
        return sheets.filter { requestedSet.contains($0.title) }
    }

    // MARK: - Pull (Sheets → Catalog)

    private func pullAll(sheets: [SheetMetadata], authProvider: GoogleAuthProvider) async throws -> Summary {
        var totalAdded = 0
        var totalRemoved = 0
        var totalUpdated = 0

        for sheet in sheets {
            let token = try await authProvider.accessToken()
            let diff = try await pullTab(tabName: sheet.title, token: token)
            totalAdded += diff.added
            totalRemoved += diff.removed
            totalUpdated += diff.updated
        }

        return Summary(tabs: sheets.count, added: totalAdded, removed: totalRemoved, updated: totalUpdated)
    }

    private func pullTab(tabName: String, token: String) async throws -> PullDiff {
        SyncLogger.info("[\(tabName)] Fetching values...")

        let rows = try await sheetsClient.getSheetValues(
            spreadsheetId: config.spreadsheetId,
            sheetName: tabName,
            token: token
        )

        let entries = SheetParser.parse(
            rows: rows,
            identifierColumn: config.effectiveIdentifierColumn
        )

        let parsedLanguages = Set(entries.flatMap { $0.translations.keys }).sorted()
        SyncLogger.info(
            "[\(tabName)] Parsed language keys from rows: \(parsedLanguages.isEmpty ? "none" : parsedLanguages.joined(separator: ", "))"
        )

        let outputPath = (config.localizationPath as NSString).appendingPathComponent("\(tabName).xcstrings")

        // Load existing catalog for diff logging.
        let existingCatalog = try StringCatalogReader.read(from: outputPath)
        let hadExistingCatalog = (existingCatalog != nil)

        let diff = SyncLogger.logPullResult(
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

        return diff
    }

    private struct Summary {
        let tabs: Int
        let added: Int
        let removed: Int
        let updated: Int
    }
}
