// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

/// A single parsed localization entry from a sheet row.
public struct ParsedEntry: Sendable, Equatable {
    /// The localization key (value from the "Identifier iOS" column).
    public let key: String
    /// Translations keyed by BCP-47 language code (e.g. "de", "en").
    /// Only languages with non-filtered values are included.
    public let translations: [String: String]

    public init(key: String, translations: [String: String]) {
        self.key = key
        self.translations = translations
    }
}

/// The column layout discovered from the header row of a sheet tab.
struct SheetColumnLayout {
    /// Index of the "Identifier iOS" column.
    let identifierIndex: Int
    /// Map of language code → column index for all language columns.
    let languageColumns: [String: Int]
}

/// Parses Google Sheets raw 2D string data into `ParsedEntry` values.
///
/// Column schema (per tab):
/// - Row 0 is the header row.
/// - `"Identifier iOS"` → the localization key.
/// - `"comments"` → always ignored.
/// - All other columns → treated as language codes.
///
/// Row filtering:
/// - Skip rows where the identifier is `""`, `"NR"`, or `"TBD"` (exact, case-sensitive).
/// - Skip rows where the identifier starts with `"//"` (section headers).
/// - For individual language cells: omit that language if the value is `""`, `"NR"`, or `"TBD"`.
public enum SheetParser {

    // MARK: - Public API

    /// Parses raw sheet values into an array of `ParsedEntry` values.
    ///
    /// - Parameters:
    ///   - rows: The 2D array of strings as returned by the Sheets API.
    /// - Returns: Array of valid entries. Empty if the sheet has no header or no data rows.
    public static func parse(rows: [[String]]) -> [ParsedEntry] {
        guard !rows.isEmpty else { return [] }

        let headerRow = rows[0].map { $0.trimmingCharacters(in: .whitespaces) }
        guard let layout = discoverColumns(headerRow: headerRow) else {
            SyncLogger.info("No Columns found!")
            return []
        }

        var entries: [ParsedEntry] = []
        for row in rows.dropFirst() {
            SyncLogger.info("Row: \(row)")
            if let entry = parseRow(row, layout: layout) {
                entries.append(entry)
            }
        }
        return entries
    }

    // MARK: - Column layout discovery

    static func discoverColumns(headerRow: [String]) -> SheetColumnLayout? {
        guard let identifierIndex = headerRow.firstIndex(of: "Identifier iOS") else {
            return nil
        }

        var languageColumns: [String: Int] = [:]
        for (index, header) in headerRow.enumerated() {
            guard index != identifierIndex else { continue }
            guard header != "comments" else { continue }
            guard !header.isEmpty else { continue }
            languageColumns[header] = index
        }

        return SheetColumnLayout(
            identifierIndex: identifierIndex,
            languageColumns: languageColumns
        )
    }

    // MARK: - Row parsing

    static func parseRow(_ row: [String], layout: SheetColumnLayout) -> ParsedEntry? {
        let identifier = cellValue(row, at: layout.identifierIndex)
        guard shouldIncludeIdentifier(identifier) else { return nil }

        var translations: [String: String] = [:]
        for (language, columnIndex) in layout.languageColumns {
            let value = cellValue(row, at: columnIndex)
            if shouldIncludeTranslationValue(value) {
                translations[language] = value
            }
        }

        return ParsedEntry(key: identifier, translations: translations)
    }

    // MARK: - Filter helpers

    /// Returns the cell value at the given index, or empty string if the row is too short.
    static func cellValue(_ row: [String], at index: Int) -> String {
        guard index < row.count else { return "" }
        return row[index].trimmingCharacters(in: .whitespaces)
    }

    /// Returns `true` if the identifier should produce a `ParsedEntry`.
    static func shouldIncludeIdentifier(_ value: String) -> Bool {
        guard !isFilteredValue(value) else { return false }
        guard !value.hasPrefix("//") else { return false }
        return true
    }

    /// Returns `true` if the translation value should be included in `translations`.
    static func shouldIncludeTranslationValue(_ value: String) -> Bool {
        return !isFilteredValue(value)
    }

    /// Returns `true` for values that must be ignored: empty, "NR", "TBD".
    static func isFilteredValue(_ value: String) -> Bool {
        return value.isEmpty || value == "NR" || value == "TBD"
    }
}
