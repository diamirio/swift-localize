// Copyright 2026 DIAMIR. All rights reserved.

import XCTest
@testable import swift_localize

// MARK: - SheetParser tests

final class SheetParserTests: XCTestCase {

    // MARK: Column discovery

    func test_discoverColumns_findsIdentifierAndLanguages() {
        let header = ["Identifier iOS", "de", "en", "fr", "comments"]
        let layout = SheetParser.discoverColumns(headerRow: header)

        XCTAssertNotNil(layout)
        XCTAssertEqual(layout?.identifierIndex, 0)
        XCTAssertEqual(layout?.languageColumns["de"], 1)
        XCTAssertEqual(layout?.languageColumns["en"], 2)
        XCTAssertEqual(layout?.languageColumns["fr"], 3)
        // "comments" must not be treated as a language
        XCTAssertNil(layout?.languageColumns["comments"])
    }

    func test_discoverColumns_returnsNilWhenNoIdentifierColumn() {
        let header = ["Key", "de", "en", "comments"]
        XCTAssertNil(SheetParser.discoverColumns(headerRow: header))
    }

    func test_discoverColumns_ignoresEmptyHeaders() {
        let header = ["Identifier iOS", "", "de", "comments"]
        let layout = SheetParser.discoverColumns(headerRow: header)
        XCTAssertNil(layout?.languageColumns[""])
        XCTAssertEqual(layout?.languageColumns["de"], 2)
    }

    // MARK: Row filtering — identifier

    func test_shouldIncludeIdentifier_excludesEmpty() {
        XCTAssertFalse(SheetParser.shouldIncludeIdentifier(""))
    }

    func test_shouldIncludeIdentifier_excludesNR() {
        XCTAssertFalse(SheetParser.shouldIncludeIdentifier("NR"))
    }

    func test_shouldIncludeIdentifier_excludesTBD() {
        XCTAssertFalse(SheetParser.shouldIncludeIdentifier("TBD"))
    }

    func test_shouldIncludeIdentifier_excludesSectionHeaders() {
        XCTAssertFalse(SheetParser.shouldIncludeIdentifier("// Section title"))
        XCTAssertFalse(SheetParser.shouldIncludeIdentifier("//nospace"))
    }

    func test_shouldIncludeIdentifier_includesValidKey() {
        XCTAssertTrue(SheetParser.shouldIncludeIdentifier("home.title"))
        XCTAssertTrue(SheetParser.shouldIncludeIdentifier("some_key"))
    }

    func test_shouldIncludeIdentifier_isCaseSensitive() {
        // lowercase "nr" and "tbd" should NOT be filtered
        XCTAssertTrue(SheetParser.shouldIncludeIdentifier("nr"))
        XCTAssertTrue(SheetParser.shouldIncludeIdentifier("tbd"))
    }

    // MARK: Row filtering — translation values

    func test_shouldIncludeTranslationValue_excludesFilteredValues() {
        XCTAssertFalse(SheetParser.shouldIncludeTranslationValue(""))
        XCTAssertFalse(SheetParser.shouldIncludeTranslationValue("NR"))
        XCTAssertFalse(SheetParser.shouldIncludeTranslationValue("TBD"))
    }

    func test_shouldIncludeTranslationValue_includesNormalValues() {
        XCTAssertTrue(SheetParser.shouldIncludeTranslationValue("Hallo"))
        XCTAssertTrue(SheetParser.shouldIncludeTranslationValue("Hello World"))
    }

    // MARK: Full parse

    func test_parse_emptyInput() {
        XCTAssertTrue(SheetParser.parse(rows: []).isEmpty)
    }

    func test_parse_headerOnlyNoData() {
        let rows = [["Identifier iOS", "de", "en", "comments"]]
        XCTAssertTrue(SheetParser.parse(rows: rows).isEmpty)
    }

    func test_parse_basicEntries() {
        let rows = [
            ["Identifier iOS", "de", "en", "comments"],
            ["home.title", "Startseite", "Home", "Main screen title"],
            ["home.subtitle", "Willkommen", "Welcome", ""],
        ]
        let entries = SheetParser.parse(rows: rows)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].key, "home.title")
        XCTAssertEqual(entries[0].translations["de"], "Startseite")
        XCTAssertEqual(entries[0].translations["en"], "Home")
        // "comments" column must not appear in translations
        XCTAssertNil(entries[0].translations["comments"])
    }

    func test_parse_skipsFilteredIdentifiers() {
        let rows = [
            ["Identifier iOS", "de", "en", "comments"],
            ["// Section", "ignored", "ignored", ""],
            ["NR", "ignored", "ignored", ""],
            ["TBD", "ignored", "ignored", ""],
            ["", "ignored", "ignored", ""],
            ["valid.key", "Wert", "Value", ""],
        ]
        let entries = SheetParser.parse(rows: rows)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].key, "valid.key")
    }

    func test_parse_omitsFilteredLanguageValues() {
        let rows = [
            ["Identifier iOS", "de", "en", "comments"],
            ["key.one", "Hallo", "NR", ""],
            ["key.two", "TBD", "", ""],
        ]
        let entries = SheetParser.parse(rows: rows)

        // key.one: "de" present, "en" omitted (NR)
        let entry1 = entries.first { $0.key == "key.one" }
        XCTAssertNotNil(entry1)
        XCTAssertEqual(entry1?.translations["de"], "Hallo")
        XCTAssertNil(entry1?.translations["en"])

        // key.two: both values filtered → entry still present, translations empty
        let entry2 = entries.first { $0.key == "key.two" }
        XCTAssertNotNil(entry2)
        XCTAssertTrue(entry2?.translations.isEmpty ?? false)
    }

    func test_parse_handlesShortRows() {
        let rows = [
            ["Identifier iOS", "de", "en", "comments"],
            ["key.short"],
        ]
        let entries = SheetParser.parse(rows: rows)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].key, "key.short")
        XCTAssertTrue(entries[0].translations.isEmpty)
    }

    func test_parse_trimsWhitespace() {
        let rows = [
            ["Identifier iOS", "de", "comments"],
            ["  key.trimmed  ", "  Hallo  ", ""],
        ]
        let entries = SheetParser.parse(rows: rows)
        XCTAssertEqual(entries[0].key, "key.trimmed")
        XCTAssertEqual(entries[0].translations["de"], "Hallo")
    }
}

// MARK: - StringCatalogWriter tests

final class StringCatalogWriterTests: XCTestCase {

    func test_buildCatalog_correctStructure() {
        let entries = [
            ParsedEntry(key: "app.name", translations: ["de": "App Name", "en": "App Name"]),
            ParsedEntry(key: "app.slogan", translations: ["de": "Unser Slogan"]),
        ]
        let catalog = StringCatalogWriter.buildCatalog(entries: entries, sourceLanguage: "de")

        XCTAssertEqual(catalog.sourceLanguage, "de")
        XCTAssertEqual(catalog.version, "1.0")
        XCTAssertEqual(catalog.strings.count, 2)

        let appName = catalog.strings["app.name"]
        XCTAssertNotNil(appName)
        XCTAssertEqual(appName?.localizations?["de"]?.stringUnit.value, "App Name")
        XCTAssertEqual(appName?.localizations?["en"]?.stringUnit.value, "App Name")
        XCTAssertEqual(appName?.localizations?["de"]?.stringUnit.state, .translated)
    }

    func test_buildCatalog_emptyTranslationsProducesNilLocalizations() {
        let entries = [ParsedEntry(key: "empty.key", translations: [:])]
        let catalog = StringCatalogWriter.buildCatalog(entries: entries, sourceLanguage: "de")
        XCTAssertNil(catalog.strings["empty.key"]?.localizations)
    }

    func test_encode_producesValidJSON() throws {
        let entries = [ParsedEntry(key: "a.key", translations: ["de": "Hallo"])]
        let catalog = StringCatalogWriter.buildCatalog(entries: entries, sourceLanguage: "de")
        let data = try StringCatalogWriter.encode(catalog)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["sourceLanguage"] as? String, "de")
        XCTAssertEqual(json?["version"] as? String, "1.0")
    }
}

// MARK: - StringCatalogModel Codable tests

final class StringCatalogModelTests: XCTestCase {

    func test_roundtrip_encodeDecode() throws {
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
        XCTAssertEqual(decoded.sourceLanguage, "de")
        XCTAssertEqual(decoded.strings["hello"]?.localizations?["de"]?.stringUnit.value, "Hallo")
        XCTAssertEqual(decoded.strings["hello"]?.localizations?["en"]?.stringUnit.value, "Hello")
    }
}

// MARK: - PEMKeyDecoder tests

final class PEMKeyDecoderTests: XCTestCase {

    func test_decodeRSAPrivateKeyData_acceptsPKCS1PEM() throws {
        let pkcs1 = Data([0x30, 0x03, 0x02, 0x01, 0x00])
        let pem = makePEM(header: "RSA PRIVATE KEY", body: pkcs1)

        let decoded = try PEMKeyDecoder.decodeRSAPrivateKeyData(from: pem)
        XCTAssertEqual(decoded, pkcs1)
    }

    func test_decodeRSAPrivateKeyData_extractsInnerKeyFromPKCS8() throws {
        let pkcs1 = Data([0x30, 0x03, 0x02, 0x01, 0x00])
        let pkcs8 = Data([
            0x30, 0x19,
            0x02, 0x01, 0x00,
            0x30, 0x0D,
            0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,
            0x05, 0x00,
            0x04, 0x05, 0x30, 0x03, 0x02, 0x01, 0x00,
        ])
        let pem = makePEM(header: "PRIVATE KEY", body: pkcs8)

        let decoded = try PEMKeyDecoder.decodeRSAPrivateKeyData(from: pem)
        XCTAssertEqual(decoded, pkcs1)
    }

    func test_decodeRSAPrivateKeyData_supportsEscapedNewlines() throws {
        let pkcs1 = Data([0x30, 0x03, 0x02, 0x01, 0x00])
        let pem = makePEM(header: "RSA PRIVATE KEY", body: pkcs1)
            .replacingOccurrences(of: "\n", with: "\\n")

        let decoded = try PEMKeyDecoder.decodeRSAPrivateKeyData(from: pem)
        XCTAssertEqual(decoded, pkcs1)
    }

    func test_decodeRSAPrivateKeyData_rejectsEncryptedPrivateKey() {
        let pem = """
        -----BEGIN ENCRYPTED PRIVATE KEY-----
        AAAA
        -----END ENCRYPTED PRIVATE KEY-----
        """

        XCTAssertThrowsError(try PEMKeyDecoder.decodeRSAPrivateKeyData(from: pem)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(message.contains("Encrypted private keys are not supported."))
        }
    }

    func test_decodeRSAPrivateKeyData_rejectsUnsupportedHeader() {
        let pem = """
        -----BEGIN EC PRIVATE KEY-----
        AAAA
        -----END EC PRIVATE KEY-----
        """

        XCTAssertThrowsError(try PEMKeyDecoder.decodeRSAPrivateKeyData(from: pem)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(message.contains("Unsupported PEM header"))
        }
    }

    private func makePEM(header: String, body: Data) -> String {
        """
        -----BEGIN \(header)-----
        \(body.base64EncodedString())
        -----END \(header)-----
        """
    }
}

// MARK: - XLIFFService tests

final class XLIFFServiceTests: XCTestCase {

    func test_applyTranslations_updatesTargetNodes() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let enPath = (tempDir as NSString).appendingPathComponent("en.xliff")
        try enDocument().write(toFile: enPath, atomically: true, encoding: .utf8)

        let updates = try XLIFFService.applyTranslations(
            [
                "home.title": ["en": "Homepage"],
                "home.subtitle": ["en": "Welcome back"],
            ],
            sourceLanguage: "de",
            in: tempDir
        )

        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0].updatedUnitCount, 2)

        let reloaded = try String(contentsOfFile: enPath, encoding: .utf8)
        XCTAssertTrue(reloaded.contains("<target>Homepage</target>"))
        XCTAssertTrue(reloaded.contains("<target>Welcome back</target>"))
    }

    func test_applyTranslations_updatesSourceWhenNoTargetLanguage() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let basePath = (tempDir as NSString).appendingPathComponent("base.xliff")
        try baseDocument().write(toFile: basePath, atomically: true, encoding: .utf8)

        let updates = try XLIFFService.applyTranslations(
            [
                "home.title": ["de": "Start"],
            ],
            sourceLanguage: "de",
            in: tempDir
        )

        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0].updatedUnitCount, 1)

        let reloaded = try String(contentsOfFile: basePath, encoding: .utf8)
        XCTAssertTrue(reloaded.contains("<source>Start</source>"))
    }

    private func makeTempDirectory() throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-localize-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir.path
    }

    private func deDocument() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <xliff version="1.2">
          <file original="Localizable.strings" source-language="de" target-language="de" datatype="plaintext">
            <body>
              <trans-unit id="home.title">
                <source>Startseite</source>
                <target>Startseite</target>
              </trans-unit>
              <trans-unit id="home.subtitle">
                <source>Willkommen</source>
                <target>Willkommen</target>
              </trans-unit>
            </body>
          </file>
        </xliff>
        """
    }

    private func enDocument() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <xliff version="1.2">
          <file original="Localizable.strings" source-language="de" target-language="en" datatype="plaintext">
            <body>
              <trans-unit id="home.title">
                <source>Startseite</source>
                <target>Home</target>
              </trans-unit>
              <trans-unit id="home.subtitle">
                <source>Willkommen</source>
                <target>Welcome</target>
              </trans-unit>
            </body>
          </file>
        </xliff>
        """
    }

    private func baseDocument() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <xliff version="1.2">
          <file original="Localizable.strings" source-language="de" datatype="plaintext">
            <body>
              <trans-unit id="home.title">
                <source>Startseite</source>
              </trans-unit>
            </body>
          </file>
        </xliff>
        """
    }
}
