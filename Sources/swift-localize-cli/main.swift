// Copyright 2026 DIAMIR. All rights reserved.

import Foundation
import swift_localize

// MARK: - Usage

func printUsage() {
    print("""
    USAGE: swift-localize-cli [--config <path>]

    OPTIONS:
      --config <path>           Path to localize.json config file.
                                Defaults to ./localize.json in the current directory.
      --help                    Show this help message.

    CONFIG FILE (localize.json):
      {
        "credentialsPath": "./credentials/google_drive_credentials.json",
        "spreadsheetId":   "YOUR_SPREADSHEET_ID",
        "outputDirectory": "./output",
        "sourceLanguage":  "de",
        "xcodeProjectPath": "./YourApp.xcodeproj"
      }

      For workspaces use:
      {
        "credentialsPath": "./credentials/google_drive_credentials.json",
        "spreadsheetId":   "YOUR_SPREADSHEET_ID",
        "outputDirectory": "./output",
        "sourceLanguage":  "de",
        "xcodeWorkspacePath": "./YourApp.xcworkspace",
        "xcodeScheme": "YourApp"
      }

      For this repo (no Xcode project): omit xcodeProjectPath/xcodeWorkspacePath.
      The tool then uses local artifacts in outputDirectory (XLIFF if present,
      otherwise .xcstrings fallback).
    """)
}

// MARK: - Argument parsing

struct CLIArguments {
    let configPath: String
}

func parseArguments(_ args: [String]) -> CLIArguments? {
    var configPath = "./localize.json"

    var index = 1 // skip argv[0]
    while index < args.count {
        switch args[index] {
        case "--help", "-h":
            printUsage()
            exit(0)
        case "--config":
            index += 1
            guard index < args.count else {
                fputs("Error: --config requires a file path.\n", stderr)
                return nil
            }
            configPath = args[index]
        default:
            fputs("Error: Unknown argument '\(args[index])'.\n", stderr)
            return nil
        }
        index += 1
    }

    return CLIArguments(configPath: configPath)
}

// MARK: - Entry point

guard let arguments = parseArguments(CommandLine.arguments) else {
    printUsage()
    exit(1)
}

do {
    let config = try LocalizerConfig.load(from: arguments.configPath)
    let localizer = Localizer(config: config)
    try await localizer.run()
} catch {
    SyncLogger.error(error.localizedDescription)
    exit(1)
}
