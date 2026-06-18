// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

/// A translation value for a single language: either a flat string or a set of plural variations.
public enum TranslationValue: Sendable, Equatable {
    case single(String)
    case plural([PluralCategory: String])
}

/// A single parsed localization entry from a sheet row.
public struct ParsedEntry: Sendable, Equatable {
    /// The localization key (value from the identifier column).
    public let key: String
    /// Translations keyed by BCP-47 language code (e.g. "de", "en").
    /// Only languages with non-filtered values are included.
    public let translations: [String: TranslationValue]
    /// Optional comment from the "Kommentar" column.
    public let comment: String?

    public init(key: String, translations: [String: TranslationValue], comment: String? = nil) {
        self.key = key
        self.translations = translations
        self.comment = comment
    }
}

/// The column layout discovered from the header row of a sheet tab.
struct SheetColumnLayout {
    /// Index of the identifier column.
    let identifierIndex: Int
    /// Map of language code → column index for all language columns.
    let languageColumns: [String: Int]
    /// Index of the "Kommentar" column.
    let commentIndex: Int
}

/// Parses Google Sheets raw 2D string data into `ParsedEntry` values.
///
/// Column schema (per tab):
/// - Row 0 is the header row.
/// - Identifier column (default `"Identifier iOS"`, configurable) → the localization key.
/// - `"Kommentar"` → optional string comment on each entry.
/// - Columns before `"Kommentar"` with valid short language codes are treated as language columns.
/// - All columns after `"Kommentar"` are ignored.
///
/// Row filtering:
/// - Skip rows where the identifier is `""`, `"NR"`, or `"TBD"` (exact, case-sensitive).
/// - Skip rows where the identifier starts with `"//"` (section headers).
/// - For individual language cells: omit that language if the value is `""`, `"NR"`, or `"TBD"`.
///
/// Value processing per cell:
/// - Plural cells (`one|<value>`, `other|<value>`, ...) are mapped to `.plural`.
/// - All other cells are mapped to `.single`.
/// - `%s` / `%<N>s` placeholders are remapped to Apple's `%@` / `%<N>$@` form.
public enum SheetParser {

    private static let validShortLanguageCodes = Set(Locale.LanguageCode.isoLanguageCodes.map { $0.identifier.lowercased() })

    // MARK: - Public API

    /// Parses raw sheet values into an array of `ParsedEntry` values.
    ///
    /// - Parameters:
    ///   - rows: The 2D array of strings as returned by the Sheets API.
    ///   - identifierColumn: Header name of the identifier column. Defaults to `"Identifier iOS"`.
    /// - Returns: Array of valid entries. Empty if the sheet has no header or no data rows.
    public static func parse(
        rows: [[String]],
        identifierColumn: String = "Identifier iOS"
    ) -> [ParsedEntry] {
        guard !rows.isEmpty else { return [] }

        let headerRow = rows[0].map { $0.trimmingCharacters(in: .whitespaces) }
        SyncLogger.info("Sheet header row: \(headerRow)")
        guard let layout = discoverColumns(headerRow: headerRow, identifierColumn: identifierColumn) else {
            SyncLogger.info("No Columns found! (expected identifier column '\(identifierColumn)' and 'Kommentar')")
            return []
        }

        let discoveredLanguages = layout.languageColumns.keys.sorted()
        SyncLogger.info(
            "Discovered language columns: \(discoveredLanguages.isEmpty ? "none" : discoveredLanguages.joined(separator: ", "))"
        )

        var entries: [ParsedEntry] = []
        for row in rows.dropFirst() {
            if let entry = parseRow(row, layout: layout) {
                entries.append(entry)
            }
        }
        return entries
    }

    // MARK: - Column layout discovery

    static func discoverColumns(
        headerRow: [String],
        identifierColumn: String = "Identifier iOS"
    ) -> SheetColumnLayout? {
        guard let identifierIndex = headerRow.firstIndex(of: identifierColumn) else {
            return nil
        }
        guard let commentIndex = headerRow.firstIndex(of: "Kommentar") else {
            return nil
        }

        var languageColumns: [String: Int] = [:]
        var ignoredNonLanguageHeaders: [String] = []
        for (index, header) in headerRow.enumerated() {
            guard index != identifierIndex else { continue }
            guard index < commentIndex else { continue }
            guard !header.isEmpty else { continue }
            guard isValidShortLanguageCode(header) else {
                ignoredNonLanguageHeaders.append(header)
                continue
            }
            languageColumns[header.lowercased()] = index
        }

        if !ignoredNonLanguageHeaders.isEmpty {
            SyncLogger.warning(
                "Ignoring non-language header(s) before 'Kommentar': \(ignoredNonLanguageHeaders.joined(separator: ", "))"
            )
        }

        return SheetColumnLayout(
            identifierIndex: identifierIndex,
            languageColumns: languageColumns,
            commentIndex: commentIndex
        )
    }

    // MARK: - Row parsing

    static func parseRow(_ row: [String], layout: SheetColumnLayout) -> ParsedEntry? {
        let identifier = cellValue(row, at: layout.identifierIndex)
        guard shouldIncludeIdentifier(identifier) else { return nil }

        var translations: [String: TranslationValue] = [:]
        for (language, columnIndex) in layout.languageColumns {
            let rawValue = cellValue(row, at: columnIndex)
            guard shouldIncludeTranslationValue(rawValue) else { continue }

            switch PluralParser.parse(rawValue) {
            case .single(let value):
                translations[language] = .single(PlaceholderMapper.mapped(value))
            case .plural(let variants):
                let mapped = variants.mapValues { PlaceholderMapper.mapped($0) }
                translations[language] = .plural(mapped)
            }
        }

        let rawComment = cellValue(row, at: layout.commentIndex)
        let comment = rawComment.isEmpty ? nil : rawComment

        return ParsedEntry(key: identifier, translations: translations, comment: comment)
    }

    // MARK: - Filter helpers

    /// Returns the cell value at the given index, or empty string if the row is too short.
    /// Identifier cells are whitespace-trimmed; translation cells trim only leading/trailing
    /// whitespace but preserve embedded newlines (needed for plural cells).
    static func cellValue(_ row: [String], at index: Int) -> String {
        guard index < row.count else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
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

    static func isValidShortLanguageCode(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalized.isEmpty else { return false }
        guard !normalized.contains("-"), !normalized.contains("_") else { return false }
        return validShortLanguageCodes.contains(normalized)
    }
}
