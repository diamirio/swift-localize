// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

/// Structured log output for localization sync operations.
///
/// All output goes to stdout via `print`. Each line is prefixed with the tab/catalog name
/// in brackets for easy filtering.
public enum SyncLogger {

    // MARK: - Pull (Sheets → Catalog)

    /// Logs the diff between an old catalog and newly parsed sheet entries.
    public static func logPullResult(
        tabName: String,
        newEntries: [ParsedEntry],
        oldCatalog: StringCatalog?
    ) {
        let newKeys = Set(newEntries.map(\.key))
        let oldKeys: Set<String>

        if let old = oldCatalog {
            oldKeys = StringCatalogReader.allKeys(in: old)
        } else {
            oldKeys = []
            print("[\(tabName)] New catalog (no previous file found)")
        }

        let added = newKeys.subtracting(oldKeys).sorted()
        let removed = oldKeys.subtracting(newKeys).sorted()

        // Find updated keys: key exists in both, but at least one language value changed.
        let oldTranslations = oldCatalog.map { StringCatalogReader.translations(in: $0) } ?? [:]
        let newTranslationsMap = Dictionary(uniqueKeysWithValues: newEntries.map { ($0.key, $0.translations) })

        let commonKeys = newKeys.intersection(oldKeys)
        let updated = commonKeys.filter { key in
            guard let oldLangs = oldTranslations[key],
                  let newLangs = newTranslationsMap[key] else { return false }
            return oldLangs != newLangs
        }.sorted()

        print("[\(tabName)] \(newKeys.count) string(s) written")

        if !added.isEmpty {
            print("[\(tabName)] + added (\(added.count)): \(added.joined(separator: ", "))")
        }
        if !removed.isEmpty {
            print("[\(tabName)] - removed (\(removed.count)): \(removed.joined(separator: ", "))")
        }
        if !updated.isEmpty {
            print("[\(tabName)] ~ updated (\(updated.count)): \(updated.joined(separator: ", "))")
        }
        if added.isEmpty && removed.isEmpty && updated.isEmpty && oldCatalog != nil {
            print("[\(tabName)] No changes")
        }
    }

    // MARK: - General

    /// Logs a top-level info message (not tab-specific).
    public static func info(_ message: String) {
        print("[swift-localize] \(message)")
    }

    /// Logs a warning.
    public static func warning(_ message: String) {
        print("[swift-localize] WARNING: \(message)")
    }

    /// Logs an error.
    public static func error(_ message: String) {
        fputs("[swift-localize] ERROR: \(message)\n", stderr)
    }
}
