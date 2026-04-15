// Copyright 2026 DIAMIR. All rights reserved.

import Foundation

/// Errors from running `xcodebuild` localization commands.
public enum XcodeLocalizationError: Error, LocalizedError {
    case invalidConfiguration(String)
    case commandFailed(command: String, status: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid Xcode localization configuration: \(message)"
        case .commandFailed(let command, let status, let output):
            if output.isEmpty {
                return "xcodebuild command failed (\(status)): \(command)"
            }
            return "xcodebuild command failed (\(status)): \(command)\n\(output)"
        }
    }
}

/// Wrapper around `xcodebuild -exportLocalizations` and `-importLocalizations`.
public struct XcodeLocalizationService: Sendable {
    public init() {}

    public func exportLocalizations(config: LocalizerConfig, localizationPath: String) throws {
        try ensureDirectoryExists(at: localizationPath)
        var arguments = try baseArguments(for: config)
        arguments += [
            "-exportLocalizations",
            "-localizationPath", localizationPath,
        ]
        try runXcodebuild(arguments: arguments)
    }

    private func ensureDirectoryExists(at path: String) throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false

        if fm.fileExists(atPath: path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return
            }
            throw XcodeLocalizationError.invalidConfiguration(
                "'outputDirectory' points to a file, expected a directory: \(path)"
            )
        }

        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    public func importLocalizations(config: LocalizerConfig, localizationPath: String) throws {
        var arguments = try baseArguments(for: config)
        arguments += [
            "-importLocalizations",
            "-localizationPath", localizationPath,
        ]
        try runXcodebuild(arguments: arguments)
    }

    private func baseArguments(for config: LocalizerConfig) throws -> [String] {
        let projectPath = sanitized(config.xcodeProjectPath)
        let workspacePath = sanitized(config.xcodeWorkspacePath)
        let scheme = sanitized(config.xcodeScheme)

        if projectPath == nil && workspacePath == nil {
            throw XcodeLocalizationError.invalidConfiguration(
                "Set either 'xcodeProjectPath' or 'xcodeWorkspacePath'."
            )
        }
        if projectPath != nil && workspacePath != nil {
            throw XcodeLocalizationError.invalidConfiguration(
                "Set only one of 'xcodeProjectPath' or 'xcodeWorkspacePath'."
            )
        }

        var arguments: [String] = []

        if let projectPath {
            arguments += ["-project", projectPath]
            if let scheme {
                arguments += ["-scheme", scheme]
            }
            return arguments
        }

        guard let workspacePath else {
            throw XcodeLocalizationError.invalidConfiguration(
                "Workspace path could not be resolved."
            )
        }
        guard let scheme else {
            throw XcodeLocalizationError.invalidConfiguration(
                "'xcodeScheme' is required when using 'xcodeWorkspacePath'."
            )
        }

        arguments += ["-workspace", workspacePath, "-scheme", scheme]
        return arguments
    }

    private func runXcodebuild(arguments: [String]) throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-localize-xcodebuild-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xcodebuild"] + arguments
        process.standardOutput = outputHandle
        process.standardError = outputHandle

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
            throw XcodeLocalizationError.commandFailed(
                command: "xcodebuild \(arguments.joined(separator: " "))",
                status: process.terminationStatus,
                output: output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
