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

    /// Writes a `.xcstrings` file to an explicit output path.
    ///
    /// - Parameters:
    ///   - entries: Parsed entries from the sheet.
    ///   - outputPath: Full path (including filename) to write the `.xcstrings` file.
    ///   - sourceLanguage: The `sourceLanguage` to embed in the catalog.
    public static func write(
        entries: [ParsedEntry],
        to outputPath: String,
        sourceLanguage: String
    ) throws {
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
        let directory = outputURL.deletingLastPathComponent().path
        if !fm.fileExists(atPath: directory) {
            do {
                try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
            } catch {
                throw StringCatalogWriterError.cannotCreateOutputDirectory(directory)
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
                localizations[language] = localization(from: value)
            }
            strings[entry.key] = StringEntry(
                localizations: localizations.isEmpty ? nil : localizations,
                comment: entry.comment
            )
        }

        return StringCatalog(sourceLanguage: sourceLanguage, version: "1.0", strings: strings)
    }

    static func localization(from value: TranslationValue) -> Localization {
        switch value {
        case .single(let string):
            return Localization(
                stringUnit: StringUnit(state: .translated, value: string)
            )
        case .plural(let variants):
            var plural: [String: PluralVariation] = [:]
            for (category, text) in variants {
                plural[category.rawValue] = PluralVariation(
                    stringUnit: StringUnit(state: .translated, value: text)
                )
            }
            return Localization(variations: Variations(plural: plural))
        }
    }

    /// Encodes a `StringCatalog` to pretty-printed, sorted-key JSON.
    static func encode(_ catalog: StringCatalog) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(catalog)
    }
}
