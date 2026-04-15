// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

/// Errors thrown while reading or mutating XLIFF documents.
public enum XLIFFServiceError: Error, LocalizedError {
    case directoryNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound(let path):
            return "XLIFF directory not found: \(path)"
        }
    }
}

/// Per-file update summary for XLIFF writes.
public struct XLIFFUpdateResult: Sendable, Equatable {
    public let filePath: String
    public let language: String
    public let updatedUnitCount: Int
}

/// Utilities for applying localization values to XLIFF files.
public enum XLIFFService {

    /// Returns all `.xliff` files found recursively in `directory`.
    public static func xliffFilePaths(in directory: String) throws -> [String] {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw XLIFFServiceError.directoryNotFound(directory)
        }

        let rootURL = URL(fileURLWithPath: directory)
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var paths: [String] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "xliff" else { continue }
            paths.append(fileURL.path)
        }
        return paths.sorted()
    }

    /// Applies translations to all XLIFF files in `directory`.
    ///
    /// For target language files, values are written to `<target>`.
    /// For source language files (no target language), values are written to `<source>`.
    @discardableResult
    public static func applyTranslations(
        _ translationsByKey: [String: [String: String]],
        sourceLanguage: String,
        in directory: String
    ) throws -> [XLIFFUpdateResult] {
        var results: [XLIFFUpdateResult] = []

        for filePath in try xliffFilePaths(in: directory) {
            let doc = try xmlDocument(at: filePath)
            var updatedCount = 0
            var fileLanguage = sourceLanguage

            for fileElement in fileElements(in: doc) {
                let sourceLang = normalized(fileElement.attribute(forName: "source-language")?.stringValue)
                    ?? sourceLanguage
                let targetLang = normalized(fileElement.attribute(forName: "target-language")?.stringValue)
                let language = targetLang ?? sourceLang
                fileLanguage = language

                let writesToSource = (targetLang == nil) || (targetLang == sourceLang)
                let elementToWrite = writesToSource ? "source" : "target"

                for unit in transUnits(in: fileElement) {
                    guard let id = normalized(unit.attribute(forName: "id")?.stringValue) else { continue }
                    guard let value = translationsByKey[id]?[language] else { continue }
                    if setText(in: unit, childName: elementToWrite, to: value) {
                        updatedCount += 1
                    }
                }
            }

            if updatedCount > 0 {
                try write(xmlDocument: doc, to: filePath)
            }

            results.append(
                XLIFFUpdateResult(filePath: filePath, language: fileLanguage, updatedUnitCount: updatedCount)
            )
        }

        return results
    }

    // MARK: - XML helpers

    private static func xmlDocument(at path: String) throws -> XMLDocument {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try XMLDocument(data: data, options: [.nodePreserveAll])
    }

    private static func write(xmlDocument: XMLDocument, to path: String) throws {
        xmlDocument.characterEncoding = "UTF-8"
        let data = xmlDocument.xmlData(options: [])
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func fileElements(in document: XMLDocument) -> [XMLElement] {
        (try? document.nodes(forXPath: "//*[local-name()='file']"))?
            .compactMap { $0 as? XMLElement } ?? []
    }

    private static func transUnits(in fileElement: XMLElement) -> [XMLElement] {
        (try? fileElement.nodes(forXPath: ".//*[local-name()='trans-unit']"))?
            .compactMap { $0 as? XMLElement } ?? []
    }

    private static func text(in unit: XMLElement, childName: String) -> String? {
        guard let child = firstDirectChild(named: childName, in: unit) else { return nil }
        return child.stringValue
    }

    @discardableResult
    private static func setText(in unit: XMLElement, childName: String, to value: String) -> Bool {
        if let child = firstDirectChild(named: childName, in: unit) {
            if child.stringValue == value {
                return false
            }
            child.stringValue = value
            return true
        }

        let child = XMLElement(name: childName, stringValue: value)
        unit.addChild(child)
        return true
    }

    private static func firstDirectChild(named name: String, in element: XMLElement) -> XMLElement? {
        for childNode in element.children ?? [] {
            guard let child = childNode as? XMLElement else { continue }
            guard localName(of: child) == name else { continue }
            return child
        }
        return nil
    }

    private static func localName(of element: XMLElement) -> String {
        if let localName = element.localName, !localName.isEmpty {
            return localName
        }
        let name = element.name ?? ""
        if let lastComponent = name.split(separator: ":").last {
            return String(lastComponent)
        }
        return name
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
