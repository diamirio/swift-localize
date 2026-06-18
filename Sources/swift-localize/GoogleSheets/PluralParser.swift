// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

/// CLDR plural categories supported in xcstrings `variations.plural`.
public enum PluralCategory: String, Sendable, CaseIterable, Comparable {
    case zero
    case one
    case two
    case few
    case many
    case other

    public static func < (lhs: PluralCategory, rhs: PluralCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Parses sheet cells that describe pluralization rules.
///
/// Expected format (matching the legacy fastlane plugin):
/// ```
/// one|%d artist
/// other|%d artists
/// ```
/// Lines are separated by `\n`. Each line must contain a single `|` separating
/// the CLDR category (case-insensitive) from its value.
///
/// A cell is considered a plural cell when **all** non-empty lines parse as
/// valid `category|value` entries. Otherwise the cell is returned as `.single`.
public enum PluralParser {

    public static func parse(_ raw: String) -> TranslationValue {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .single("") }

        let lines = trimmed.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Must look plural-ish: at least one line contains `|` AND has a recognized category prefix.
        guard lines.contains(where: { hasPluralPrefix($0) }) else {
            return .single(raw)
        }

        var variations: [PluralCategory: String] = [:]
        for line in lines {
            guard let separatorIndex = line.firstIndex(of: "|") else {
                // Plural-looking cell with a non-plural line → treat the whole cell as single.
                return .single(raw)
            }
            let categoryRaw = line[..<separatorIndex].trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: separatorIndex)...])

            guard let category = PluralCategory(rawValue: categoryRaw) else {
                return .single(raw)
            }
            variations[category] = value
        }

        guard !variations.isEmpty else { return .single(raw) }

        // xcstrings requires `other` to be present.
        guard variations[.other] != nil else {
            SyncLogger.warning("Plural cell missing required 'other' category; treating as single string.")
            return .single(raw)
        }

        return .plural(variations)
    }

    private static func hasPluralPrefix(_ line: String) -> Bool {
        guard let separatorIndex = line.firstIndex(of: "|") else { return false }
        let categoryRaw = line[..<separatorIndex].trimmingCharacters(in: .whitespaces).lowercased()
        return PluralCategory(rawValue: categoryRaw) != nil
    }
}
