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
    ) -> PullDiff {
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

        let oldSignatures = oldCatalog.map { StringCatalogReader.translationSignatures(in: $0) } ?? [:]
        let newSignatures: [String: [String: String]] = Dictionary(uniqueKeysWithValues: newEntries.map { entry in
            (entry.key, entry.translations.mapValues { signature(for: $0) })
        })

        let commonKeys = newKeys.intersection(oldKeys)
        let updated = commonKeys.filter { key in
            oldSignatures[key] != newSignatures[key]
        }.sorted()

        print("[\(tabName)] \(newKeys.count) string(s) written")

        added.forEach { print("[\(tabName)] + added: \($0)") }
        removed.forEach { print("[\(tabName)] - removed: \($0)") }
        updated.forEach { print("[\(tabName)] ~ updated: \($0)") }
        if added.isEmpty && removed.isEmpty && updated.isEmpty && oldCatalog != nil {
            print("[\(tabName)] No changes")
        }

        return PullDiff(added: added.count, removed: removed.count, updated: updated.count)
    }

    private static func signature(for value: TranslationValue) -> String {
        switch value {
        case .single(let string):
            return "single:" + string
        case .plural(let variants):
            let joined = variants.keys.sorted().map { "\($0.rawValue)=\(variants[$0]!)" }.joined(separator: "|")
            return "plural:" + joined
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

/// Per-tab change counts, returned by `SyncLogger.logPullResult` for higher-level summarization.
public struct PullDiff: Sendable {
    public let added: Int
    public let removed: Int
    public let updated: Int

    public init(added: Int, removed: Int, updated: Int) {
        self.added = added
        self.removed = removed
        self.updated = updated
    }
}
