// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

// MARK: - Top-level catalog

/// Represents the root structure of an Xcode String Catalog (`.xcstrings`) file.
public struct StringCatalog: Codable, Sendable {
    public var sourceLanguage: String
    public var version: String
    public var strings: [String: StringEntry]

    public init(sourceLanguage: String, version: String = "1.0", strings: [String: StringEntry] = [:]) {
        self.sourceLanguage = sourceLanguage
        self.version = version
        self.strings = strings
    }
}

// MARK: - String entry

/// Represents one localization key in the catalog.
public struct StringEntry: Codable, Sendable {
    /// Per-language localization data. Absent if no translations exist yet.
    public var localizations: [String: Localization]?

    /// Optional comment (not currently populated from sheet data, reserved for future use).
    public var comment: String?

    public init(localizations: [String: Localization]? = nil, comment: String? = nil) {
        self.localizations = localizations
        self.comment = comment
    }
}

// MARK: - Localization (language variant)

/// Represents the localization for a single language.
public struct Localization: Codable, Sendable {
    public var stringUnit: StringUnit

    public init(stringUnit: StringUnit) {
        self.stringUnit = stringUnit
    }
}

// MARK: - String unit

/// The actual translated string and its review state.
public struct StringUnit: Codable, Sendable {
    public var state: TranslationState
    public var value: String

    public init(state: TranslationState = .translated, value: String) {
        self.state = state
        self.value = value
    }
}

// MARK: - Translation state

public enum TranslationState: String, Codable, Sendable {
    case translated
    case needsReview = "needs_review"
    case new
}
