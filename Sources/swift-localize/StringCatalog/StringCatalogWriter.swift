// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

/// Errors from the String Catalog writer.
public enum StringCatalogWriterError: Error, LocalizedError {
    case cannotCreateOutputDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .cannotCreateOutputDirectory(let path):
            return "Cannot create output directory: \(path)"
        }
    }
}

/// Builds and persists `.xcstrings` files from parsed sheet entries.
public enum StringCatalogWriter {

    /// Writes a `.xcstrings` file for a single sheet tab.
    ///
    /// - Parameters:
    ///   - entries: Parsed entries from the sheet.
    ///   - tabName: Name of the sheet tab; used as the output filename.
    ///   - outputDirectory: Directory where the file is written.
    ///   - sourceLanguage: The `sourceLanguage` to embed in the catalog.
    public static func write(
        entries: [ParsedEntry],
        tabName: String,
        outputDirectory: String,
        sourceLanguage: String
    ) throws {
        let fileName = "\(tabName).xcstrings"
        let outputPath = (outputDirectory as NSString).appendingPathComponent(fileName)
        let outputURL = URL(fileURLWithPath: outputPath)

        if entries.isEmpty {
            if FileManager.default.fileExists(atPath: outputPath) {
                try FileManager.default.removeItem(at: outputURL)
            }
            return
        }

        let catalog = buildCatalog(entries: entries, sourceLanguage: sourceLanguage)
        let data = try encode(catalog)

        let fm = FileManager.default
        if !fm.fileExists(atPath: outputDirectory) {
            do {
                try fm.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
            } catch {
                throw StringCatalogWriterError.cannotCreateOutputDirectory(outputDirectory)
            }
        }

        try data.write(to: outputURL, options: .atomic)
    }

    // MARK: - Internal helpers

    /// Builds a `StringCatalog` from parsed entries.
    static func buildCatalog(entries: [ParsedEntry], sourceLanguage: String) -> StringCatalog {
        var strings: [String: StringEntry] = [:]

        for entry in entries {
            var localizations: [String: Localization] = [:]
            for (language, value) in entry.translations {
                localizations[language] = Localization(
                    stringUnit: StringUnit(state: .translated, value: value)
                )
            }
            strings[entry.key] = StringEntry(
                localizations: localizations.isEmpty ? nil : localizations,
                comment: entry.comment
            )
        }

        return StringCatalog(sourceLanguage: sourceLanguage, version: "1.0", strings: strings)
    }

    /// Encodes a `StringCatalog` to pretty-printed, sorted-key JSON.
    static func encode(_ catalog: StringCatalog) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(catalog)
    }
}
