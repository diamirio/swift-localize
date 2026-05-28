// Copyright 2026 DIAMIR. All rights reserved.

import Foundation
import Security
import Testing
@testable import swift_localize

// MARK: - SheetParser

@Suite("SheetParser")
struct SheetParserTests {

    // MARK: Column discovery

    @Test
    func discoverColumns_findsIdentifierAndLanguages() {
        let header = ["Identifier iOS", "de", "en", "fr", "Kommentar"]
        let layout = SheetParser.discoverColumns(headerRow: header)

        #expect(layout != nil)
        #expect(layout?.identifierIndex == 0)
        #expect(layout?.languageColumns["de"] == 1)
        #expect(layout?.languageColumns["en"] == 2)
        #expect(layout?.languageColumns["fr"] == 3)
        #expect(layout?.commentIndex == 4)
        #expect(layout?.languageColumns["Kommentar"] == nil)
    }

    @Test
    func discoverColumns_returnsNilWhenNoIdentifierColumn() {
        let header = ["Key", "de", "en", "Kommentar"]
        #expect(SheetParser.discoverColumns(headerRow: header) == nil)
    }

    @Test
    func discoverColumns_returnsNilWhenNoKommentarColumn() {
        let header = ["Identifier iOS", "de", "en"]
        #expect(SheetParser.discoverColumns(headerRow: header) == nil)
    }

    @Test
    func discoverColumns_ignoresEmptyHeaders() {
        let header = ["Identifier iOS", "", "de", "Kommentar"]
        let layout = SheetParser.discoverColumns(headerRow: header)
        #expect(layout?.languageColumns[""] == nil)
        #expect(layout?.languageColumns["de"] == 2)
    }

    @Test
    func discoverColumns_acceptsOnlyShortLanguageCodes() {
        let header = ["Identifier iOS", "de", "en-US", "foo", "en", "Kommentar"]
        let layout = SheetParser.discoverColumns(headerRow: header)
        #expect(layout?.languageColumns["de"] == 1)
        #expect(layout?.languageColumns["en"] == 4)
        #expect(layout?.languageColumns["en-US"] == nil)
        #expect(layout?.languageColumns["foo"] == nil)
    }

    @Test
    func discoverColumns_ignoresColumnsAfterKommentar() {
        let header = ["Identifier iOS", "de", "Kommentar", "en", "fr"]
        let layout = SheetParser.discoverColumns(headerRow: header)
        #expect(layout?.languageColumns["de"] == 1)
        #expect(layout?.languageColumns["en"] == nil)
        #expect(layout?.languageColumns["fr"] == nil)
    }

    @Test
    func discoverColumns_acceptsCustomIdentifierColumn() {
        let header = ["Identifier Android", "de", "en", "Kommentar"]
        let layout = SheetParser.discoverColumns(headerRow: header, identifierColumn: "Identifier Android")
        #expect(layout?.identifierIndex == 0)
        #expect(layout?.languageColumns["de"] == 1)
    }

    // MARK: Identifier filtering

    @Test
    func shouldIncludeIdentifier_filtering() {
        #expect(SheetParser.shouldIncludeIdentifier("") == false)
        #expect(SheetParser.shouldIncludeIdentifier("NR") == false)
        #expect(SheetParser.shouldIncludeIdentifier("TBD") == false)
        #expect(SheetParser.shouldIncludeIdentifier("// Section title") == false)
        #expect(SheetParser.shouldIncludeIdentifier("//nospace") == false)
        #expect(SheetParser.shouldIncludeIdentifier("home.title") == true)
        #expect(SheetParser.shouldIncludeIdentifier("some_key") == true)
        // Case-sensitive: lowercase variants are NOT filtered.
        #expect(SheetParser.shouldIncludeIdentifier("nr") == true)
        #expect(SheetParser.shouldIncludeIdentifier("tbd") == true)
    }

    @Test
    func shouldIncludeTranslationValue_filtering() {
        #expect(SheetParser.shouldIncludeTranslationValue("") == false)
        #expect(SheetParser.shouldIncludeTranslationValue("NR") == false)
        #expect(SheetParser.shouldIncludeTranslationValue("TBD") == false)
        #expect(SheetParser.shouldIncludeTranslationValue("Hallo") == true)
        #expect(SheetParser.shouldIncludeTranslationValue("Hello World") == true)
    }

    // MARK: Full parse

    @Test
    func parse_emptyInput() {
        #expect(SheetParser.parse(rows: []).isEmpty)
    }

    @Test
    func parse_headerOnlyNoData() {
        let rows = [["Identifier iOS", "de", "en", "Kommentar"]]
        #expect(SheetParser.parse(rows: rows).isEmpty)
    }

    @Test
    func parse_basicEntries() {
        let rows = [
            ["Identifier iOS", "de", "en", "Kommentar"],
            ["home.title", "Startseite", "Home", "Main screen title"],
            ["home.subtitle", "Willkommen", "Welcome", ""],
        ]
        let entries = SheetParser.parse(rows: rows)
        #expect(entries.count == 2)
        #expect(entries[0].key == "home.title")
        #expect(entries[0].translations["de"] == .single("Startseite"))
        #expect(entries[0].translations["en"] == .single("Home"))
        #expect(entries[0].comment == "Main screen title")
        #expect(entries[0].translations["Kommentar"] == nil)
        #expect(entries[1].comment == nil)
    }

    @Test
    func parse_skipsFilteredIdentifiers() {
        let rows = [
            ["Identifier iOS", "de", "en", "Kommentar"],
            ["// Section", "ignored", "ignored", ""],
            ["NR", "ignored", "ignored", ""],
            ["TBD", "ignored", "ignored", ""],
            ["", "ignored", "ignored", ""],
            ["valid.key", "Wert", "Value", ""],
        ]
        let entries = SheetParser.parse(rows: rows)
        #expect(entries.count == 1)
        #expect(entries[0].key == "valid.key")
    }

    @Test
    func parse_omitsFilteredLanguageValues() {
        let rows = [
            ["Identifier iOS", "de", "en", "Kommentar"],
            ["key.one", "Hallo", "NR", ""],
            ["key.two", "TBD", "", ""],
        ]
        let entries = SheetParser.parse(rows: rows)

        let entry1 = entries.first { $0.key == "key.one" }
        #expect(entry1 != nil)
        #expect(entry1?.translations["de"] == .single("Hallo"))
        #expect(entry1?.translations["en"] == nil)

        // Both filtered → entry remains, translations empty.
        let entry2 = entries.first { $0.key == "key.two" }
        #expect(entry2 != nil)
        #expect(entry2?.translations.isEmpty == true)
    }

    @Test
    func parse_handlesShortRows() {
        let rows = [
            ["Identifier iOS", "de", "en", "Kommentar"],
            ["key.short"],
        ]
        let entries = SheetParser.parse(rows: rows)
        #expect(entries.count == 1)
        #expect(entries[0].key == "key.short")
        #expect(entries[0].translations.isEmpty)
    }

    @Test
    func parse_trimsWhitespace() {
        let rows = [
            ["Identifier iOS", "de", "Kommentar"],
            ["  key.trimmed  ", "  Hallo  ", ""],
        ]
        let entries = SheetParser.parse(rows: rows)
        #expect(entries[0].key == "key.trimmed")
        #expect(entries[0].translations["de"] == .single("Hallo"))
    }

    @Test
    func parse_ignoresColumnsAfterKommentar() {
        let rows = [
            ["Identifier iOS", "de", "Kommentar", "en"],
            ["home.title", "Startseite", "Main screen title", "Home"],
        ]
        let entries = SheetParser.parse(rows: rows)
        #expect(entries.count == 1)
        #expect(entries[0].translations["de"] == .single("Startseite"))
        #expect(entries[0].translations["en"] == nil)
        #expect(entries[0].comment == "Main screen title")
    }

    @Test
    func parse_mapsPlaceholders() {
        let rows = [
            ["Identifier iOS", "de", "en", "Kommentar"],
            ["greet", "Hallo %s", "Mario ate a %2s %1s", ""],
        ]
        let entries = SheetParser.parse(rows: rows)
        #expect(entries[0].translations["de"] == .single("Hallo %@"))
        #expect(entries[0].translations["en"] == .single("Mario ate a %2$@ %1$@"))
    }

    @Test
    func parse_extractsPlurals() {
        let rows = [
            ["Identifier iOS", "en", "Kommentar"],
            ["artists.count", "one|%d artist\nother|%d artists", ""],
        ]
        let entries = SheetParser.parse(rows: rows)
        let en = entries[0].translations["en"]
        guard case .plural(let variants) = en else {
            Issue.record("Expected plural translation, got \(String(describing: en))")
            return
        }
        #expect(variants[.one] == "%d artist")
        #expect(variants[.other] == "%d artists")
    }

    @Test
    func parse_acceptsCustomIdentifierColumn() {
        let rows = [
            ["Identifier Android", "de", "Kommentar"],
            ["greeting", "Hallo", ""],
        ]
        let entries = SheetParser.parse(rows: rows, identifierColumn: "Identifier Android")
        #expect(entries.count == 1)
        #expect(entries[0].key == "greeting")
    }
}

// MARK: - PlaceholderMapper

@Suite("PlaceholderMapper")
struct PlaceholderMapperTests {

    @Test
    func mapsSimpleS() {
        #expect(PlaceholderMapper.mapped("Hello %s") == "Hello %@")
    }

    @Test
    func mapsPositionalS() {
        #expect(PlaceholderMapper.mapped("Mario ate a %2s %1s") == "Mario ate a %2$@ %1$@")
    }

    @Test
    func leavesUnrelatedSpecifiersUnchanged() {
        #expect(PlaceholderMapper.mapped("Count: %d, Pi: %.2f") == "Count: %d, Pi: %.2f")
        #expect(PlaceholderMapper.mapped("Name: %@") == "Name: %@")
        #expect(PlaceholderMapper.mapped("Pos: %1$d") == "Pos: %1$d")
    }

    @Test
    func normalizesPositionalDollarS() {
        #expect(PlaceholderMapper.mapped("%1$s end") == "%1$@ end")
    }

    @Test
    func handlesNoPlaceholders() {
        #expect(PlaceholderMapper.mapped("plain text") == "plain text")
        #expect(PlaceholderMapper.mapped("") == "")
    }

    @Test
    func handlesTrailingPercent() {
        // A lone '%' should pass through.
        #expect(PlaceholderMapper.mapped("100% sure") == "100% sure")
    }
}

// MARK: - PluralParser

@Suite("PluralParser")
struct PluralParserTests {

    @Test
    func parsesValidPluralCell() {
        let result = PluralParser.parse("one|%d artist\nother|%d artists")
        guard case .plural(let variants) = result else {
            Issue.record("Expected plural")
            return
        }
        #expect(variants[.one] == "%d artist")
        #expect(variants[.other] == "%d artists")
        #expect(variants.count == 2)
    }

    @Test
    func parsesAllCategories() {
        let raw = """
        zero|none
        one|one item
        two|two items
        few|few items
        many|many items
        other|%d items
        """
        guard case .plural(let variants) = PluralParser.parse(raw) else {
            Issue.record("Expected plural")
            return
        }
        #expect(variants.count == 6)
        #expect(variants[.zero] == "none")
        #expect(variants[.other] == "%d items")
    }

    @Test
    func treatsPlainStringAsSingle() {
        let result = PluralParser.parse("just a sentence")
        #expect(result == .single("just a sentence"))
    }

    @Test
    func treatsMissingOtherAsSingle() {
        // Plural-looking but no 'other' → fall back to single.
        let raw = "one|%d artist"
        let result = PluralParser.parse(raw)
        #expect(result == .single(raw))
    }

    @Test
    func treatsUnknownCategoryAsSingle() {
        let raw = "weird|nope\nother|something"
        let result = PluralParser.parse(raw)
        #expect(result == .single(raw))
    }

    @Test
    func acceptsCaseInsensitiveCategories() {
        guard case .plural(let variants) = PluralParser.parse("One|x\nOther|y") else {
            Issue.record("Expected plural")
            return
        }
        #expect(variants[.one] == "x")
        #expect(variants[.other] == "y")
    }

    @Test
    func emptyValueProducesEmptySingle() {
        #expect(PluralParser.parse("") == .single(""))
    }
}

// MARK: - StringCatalogWriter

@Suite("StringCatalogWriter")
struct StringCatalogWriterTests {

    @Test
    func buildCatalog_singleAndMixedEntries() {
        let entries = [
            ParsedEntry(key: "app.name", translations: [
                "de": .single("App Name"),
                "en": .single("App Name"),
            ]),
            ParsedEntry(key: "app.slogan", translations: [
                "de": .single("Unser Slogan"),
            ]),
        ]
        let catalog = StringCatalogWriter.buildCatalog(entries: entries, sourceLanguage: "de")

        #expect(catalog.sourceLanguage == "de")
        #expect(catalog.version == "1.0")
        #expect(catalog.strings.count == 2)

        let appName = catalog.strings["app.name"]
        #expect(appName != nil)
        #expect(appName?.localizations?["de"]?.stringUnit?.value == "App Name")
        #expect(appName?.localizations?["en"]?.stringUnit?.value == "App Name")
        #expect(appName?.localizations?["de"]?.stringUnit?.state == .translated)
    }

    @Test
    func buildCatalog_emptyTranslationsProducesNilLocalizations() {
        let entries = [ParsedEntry(key: "empty.key", translations: [:])]
        let catalog = StringCatalogWriter.buildCatalog(entries: entries, sourceLanguage: "de")
        #expect(catalog.strings["empty.key"]?.localizations == nil)
    }

    @Test
    func buildCatalog_buildsPluralVariations() {
        let entries = [
            ParsedEntry(
                key: "artists.count",
                translations: [
                    "en": .plural([.one: "%d artist", .other: "%d artists"]),
                ]
            )
        ]
        let catalog = StringCatalogWriter.buildCatalog(entries: entries, sourceLanguage: "de")
        let en = catalog.strings["artists.count"]?.localizations?["en"]
        #expect(en?.stringUnit == nil)
        #expect(en?.variations?.plural?["one"]?.stringUnit.value == "%d artist")
        #expect(en?.variations?.plural?["other"]?.stringUnit.value == "%d artists")
    }

    @Test
    func encode_producesValidJSON() throws {
        let entries = [ParsedEntry(key: "a.key", translations: ["de": .single("Hallo")])]
        let catalog = StringCatalogWriter.buildCatalog(entries: entries, sourceLanguage: "de")
        let data = try StringCatalogWriter.encode(catalog)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["sourceLanguage"] as? String == "de")
        #expect(json?["version"] as? String == "1.0")
    }

    @Test
    func write_overwriteRemovesLanguageWhenNoLongerPresent() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let outputPath = (tempDir as NSString).appendingPathComponent("Sample.xcstrings")

        try StringCatalogWriter.write(
            entries: [ParsedEntry(key: "welcome", translations: [
                "de": .single("Willkommen"),
                "en": .single("Welcome"),
            ])],
            to: outputPath,
            sourceLanguage: "de"
        )

        try StringCatalogWriter.write(
            entries: [ParsedEntry(key: "welcome", translations: ["de": .single("Willkommen")])],
            to: outputPath,
            sourceLanguage: "de"
        )

        let catalog = try StringCatalogReader.read(from: outputPath)
        #expect(catalog?.strings["welcome"]?.localizations?["de"]?.stringUnit?.value == "Willkommen")
        #expect(catalog?.strings["welcome"]?.localizations?["en"] == nil)
    }

    @Test
    func write_emptyEntriesRemovesExistingCatalog() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let outputPath = (tempDir as NSString).appendingPathComponent("Sample.xcstrings")

        try StringCatalogWriter.write(
            entries: [ParsedEntry(key: "welcome", translations: ["de": .single("Willkommen")])],
            to: outputPath,
            sourceLanguage: "de"
        )
        #expect(FileManager.default.fileExists(atPath: outputPath))

        try StringCatalogWriter.write(entries: [], to: outputPath, sourceLanguage: "de")
        #expect(FileManager.default.fileExists(atPath: outputPath) == false)
    }

    @Test
    func write_emptyEntriesDoesNotCreateCatalog() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let outputPath = (tempDir as NSString).appendingPathComponent("Sample.xcstrings")
        try StringCatalogWriter.write(entries: [], to: outputPath, sourceLanguage: "de")
        #expect(FileManager.default.fileExists(atPath: outputPath) == false)
    }

    private func makeTempDirectory() throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-localize-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir.path
    }
}

// MARK: - StringCatalog Codable

@Suite("StringCatalog Codable")
struct StringCatalogModelTests {

    @Test
    func roundtrip_encodeDecodeWithSingles() throws {
        let catalog = StringCatalog(
            sourceLanguage: "de",
            version: "1.0",
            strings: [
                "hello": StringEntry(
                    localizations: [
                        "de": Localization(stringUnit: StringUnit(state: .translated, value: "Hallo")),
                        "en": Localization(stringUnit: StringUnit(state: .translated, value: "Hello")),
                    ]
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(catalog)

        let decoded = try JSONDecoder().decode(StringCatalog.self, from: data)
        #expect(decoded.sourceLanguage == "de")
        #expect(decoded.strings["hello"]?.localizations?["de"]?.stringUnit?.value == "Hallo")
        #expect(decoded.strings["hello"]?.localizations?["en"]?.stringUnit?.value == "Hello")
    }

    @Test
    func roundtrip_encodeDecodeWithPlurals() throws {
        let catalog = StringCatalog(
            sourceLanguage: "de",
            strings: [
                "artists.count": StringEntry(
                    localizations: [
                        "en": Localization(
                            variations: Variations(plural: [
                                "one": PluralVariation(stringUnit: StringUnit(value: "%d artist")),
                                "other": PluralVariation(stringUnit: StringUnit(value: "%d artists")),
                            ])
                        )
                    ]
                )
            ]
        )

        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(StringCatalog.self, from: data)
        let plural = decoded.strings["artists.count"]?.localizations?["en"]?.variations?.plural
        #expect(plural?["one"]?.stringUnit.value == "%d artist")
        #expect(plural?["other"]?.stringUnit.value == "%d artists")
    }
}

// MARK: - LocalizerConfig

@Suite("LocalizerConfig")
struct LocalizerConfigTests {

    @Test
    func decodes_minimumFields() throws {
        let json = #"""
        {
          "credentialsPath": "creds.json",
          "spreadsheetId": "abc",
          "localizationPath": "./out",
          "sourceLanguage": "de"
        }
        """#.data(using: .utf8)!
        let config = try JSONDecoder().decode(LocalizerConfig.self, from: json)
        #expect(config.tabs == nil)
        #expect(config.identifierColumn == nil)
        #expect(config.effectiveIdentifierColumn == "Identifier iOS")
    }

    @Test
    func decodes_optionalFields() throws {
        let json = #"""
        {
          "credentialsPath": "creds.json",
          "spreadsheetId": "abc",
          "localizationPath": "./out",
          "sourceLanguage": "de",
          "tabs": ["Common", "Onboarding"],
          "identifierColumn": "Identifier Android"
        }
        """#.data(using: .utf8)!
        let config = try JSONDecoder().decode(LocalizerConfig.self, from: json)
        #expect(config.tabs == ["Common", "Onboarding"])
        #expect(config.effectiveIdentifierColumn == "Identifier Android")
    }

    @Test
    func rebased_resolvesRelativePaths() {
        let base = URL(fileURLWithPath: "/tmp/project")
        let config = LocalizerConfig(
            credentialsPath: "./creds.json",
            spreadsheetId: "abc",
            localizationPath: "./MyApp",
            sourceLanguage: "de"
        )
        let rebased = config.rebased(relativeTo: base)
        #expect(rebased.credentialsPath == "/tmp/project/creds.json")
        #expect(rebased.localizationPath == "/tmp/project/MyApp")
    }

    @Test
    func rebased_leavesAbsolutePathsUnchanged() {
        let base = URL(fileURLWithPath: "/tmp/project")
        let config = LocalizerConfig(
            credentialsPath: "/etc/secrets/creds.json",
            spreadsheetId: "abc",
            localizationPath: "/var/data/MyApp",
            sourceLanguage: "de"
        )
        let rebased = config.rebased(relativeTo: base)
        #expect(rebased.credentialsPath == "/etc/secrets/creds.json")
        #expect(rebased.localizationPath == "/var/data/MyApp")
    }
}

// MARK: - PrivateKeyImporter

@Suite("PrivateKeyImporter")
struct PrivateKeyImporterTests {

    @Test
    func acceptsPKCS8PEM() throws {
        let key = try PrivateKeyImporter.importRSAPrivateKey(from: sampleRSAPKCS8PEM)
        try assertKeyIsRSA(key)
    }

    @Test
    func supportsEscapedNewlines() throws {
        let escapedPEM = sampleRSAPKCS8PEM.replacingOccurrences(of: "\n", with: "\\n")
        let key = try PrivateKeyImporter.importRSAPrivateKey(from: escapedPEM)
        try assertKeyIsRSA(key)
    }

    @Test
    func rejectsEncryptedPrivateKey() {
        let pem = """
        -----BEGIN ENCRYPTED PRIVATE KEY-----
        AAAA
        -----END ENCRYPTED PRIVATE KEY-----
        """

        #expect(throws: AuthError.self) {
            try PrivateKeyImporter.importRSAPrivateKey(from: pem)
        }
    }

    @Test
    func rejectsUnsupportedHeader() {
        let pem = """
        -----BEGIN EC PRIVATE KEY-----
        AAAA
        -----END EC PRIVATE KEY-----
        """

        #expect(throws: AuthError.self) {
            try PrivateKeyImporter.importRSAPrivateKey(from: pem)
        }
    }

    private func assertKeyIsRSA(_ key: SecKey) throws {
        guard let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
              let keyType = attributes[kSecAttrKeyType] else {
            Issue.record("Failed to read SecKey attributes")
            return
        }
        #expect(CFEqual(keyType as CFTypeRef, kSecAttrKeyTypeRSA))
    }

    private let sampleRSAPKCS8PEM = """
    -----BEGIN PRIVATE KEY-----
    MIICdwIBADANBgkqhkiG9w0BAQEFAASCAmEwggJdAgEAAoGBANsKZPRXZpiTxX1q
    1j+u6kSctHlaFWmLCAio6IJvXbXVKDxwNcy/xafJ/hganQXqqCazP/a5Vsm71s+H
    DDCYJa89QkSgQoiJ4QqXRMDpMfs16Ii/L3UHHRkqdlAVDCDxgq6Lzco9KKzpshuH
    3yzyEu4qhG/hWBGzLnMVNUWnqAzdAgMBAAECgYBj0BDA5zLxRCUySYTn8CUArwfu
    ZIZtWdWHXLDW/ziMq11ybQ+XBaxkET+gbEAxegS13ei/3SUXOGlil/+OBUbmA/7e
    p2ehSS5y4WJB9gteusvnj2bhel+XY5N+G6LNLq41HcX0xKJbYWenwFat8AdDssgh
    KwOy6fVU0Dg0SGbvYQJBAPH3bUcm7pMHRGoRaWJP3fLCeP3XStl6/yfHNGNxuuBt
    qH+vwskwyrAGBN3q4HY8jQLorKUoRHw6PI1cf7TZSQMCQQDnvpPQYP7413nrdY8k
    BG5EooJ1B+vmKo5KdcNOBU3YnR4VfHBJLvOLDDluyQqF8Tre87a6Hzk+kF/nZp8g
    3TyfAkEAkVHIj7MSFbuHmyxZ3nGZGvMxN0LV8UetdnZtQExNr/wr9oPYuHxVPuJe
    ielGZbx39AdJqOdGOlW/iCbFjBfzgQJABwP99ZD6Jw5e4oHsk2qO7AT/bguPWKhx
    Jk/qWbJPaP9Yqc3amFyTguIb2v67EtL6tUUrgvbvBLXaMWcp6hTIgQJBAPAIo4qJ
    stXWSHxPKWUqu4hl+vHwl7szans06i76LOQTL3sCNSXTokQC6AqAuIGBAS5KcE8J
    4KYXZAxVHJVlIlk=
    -----END PRIVATE KEY-----
    """
}
