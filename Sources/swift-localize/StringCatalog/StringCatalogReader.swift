// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

/// Reads existing `.xcstrings` files from disk.
public enum StringCatalogReader {

    /// Loads a `StringCatalog` from a `.xcstrings` file at the given path.
    /// Returns `nil` if the file does not exist.
    /// Throws if the file exists but cannot be decoded.
    public static func read(from filePath: String) throws -> StringCatalog? {
        let url = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StringCatalog.self, from: data)
    }

    /// Extracts all localization keys present in a catalog.
    public static func allKeys(in catalog: StringCatalog) -> Set<String> {
        Set(catalog.strings.keys)
    }

    /// Returns a flat map of key → [languageCode: signature] from a catalog,
    /// where `signature` is a stable string capturing either the flat value or
    /// the joined plural variants. Used for diffing only.
    public static func translationSignatures(in catalog: StringCatalog) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for (key, entry) in catalog.strings {
            guard let localizations = entry.localizations else { continue }
            var langs: [String: String] = [:]
            for (lang, localization) in localizations {
                if let unit = localization.stringUnit {
                    langs[lang] = "single:" + unit.value
                } else if let plural = localization.variations?.plural {
                    let joined = plural.keys.sorted().map { "\($0)=\(plural[$0]!.stringUnit.value)" }.joined(separator: "|")
                    langs[lang] = "plural:" + joined
                }
            }
            if !langs.isEmpty {
                result[key] = langs
            }
        }
        return result
    }
}
