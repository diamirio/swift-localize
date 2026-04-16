# swift-localize

`swift-localize` syncs translations from Google Sheets into Xcode localization artifacts.

It can:
- pull tab data from a spreadsheet,
- generate per-tab `.xcstrings` snapshots,
- apply translations to XLIFF files,
- optionally export/import localizations through `xcodebuild`.

## Requirements

- macOS 14+
- Swift 6.2 toolchain (or compatible with this package)
- A Google Cloud service account with access to Google Sheets API

## How It Works

1. Authenticate with Google using a service account JSON key.
2. Read spreadsheet tabs and values.
3. Parse translation rows (`key` + language columns).
4. Write `.xcstrings` snapshots into `outputDirectory`.
5. Apply translations into XLIFF files in `outputDirectory`.
6. If an Xcode project/workspace is configured, run Xcode export/import.

## Setup

### 1) Create Google service account credentials

1. Open Google Cloud Console and create/select a project.
2. Enable the Google Sheets API.
3. Create a service account.
4. Create and download a JSON key file.
5. Share your target Google Sheet with the service account email (Viewer is typically enough for read-only sync).

Save the JSON key file locally, for example as `./google_drive_credentials.json`.

### 2) Create `localize.json`

Create a config file in your working directory:

```json
{
  "credentialsPath": "./google_drive_credentials.json",
  "spreadsheetId": "YOUR_SPREADSHEET_ID",
  "outputDirectory": "./localization-output",
  "sourceLanguage": "de",
  "xcodeProjectPath": "./YourApp.xcodeproj"
}
```

Workspace-based setup:

```json
{
  "credentialsPath": "./google_drive_credentials.json",
  "spreadsheetId": "YOUR_SPREADSHEET_ID",
  "outputDirectory": "./localization-output",
  "sourceLanguage": "de",
  "xcodeWorkspacePath": "./YourApp.xcworkspace",
  "xcodeScheme": "YourApp"
}
```

If you omit both `xcodeProjectPath` and `xcodeWorkspacePath`, the tool skips Xcode export/import and only operates on local artifacts in `outputDirectory`.

## Run as CLI

From the package root:

```sh
swift run swift-localize-cli
```

Use a custom config path:

```sh
swift run swift-localize-cli --config /path/to/localize.json
```

Show help:

```sh
swift run swift-localize-cli --help
```

Build a release binary:

```sh
swift build -c release
```

Binary location:

```text
.build/release/swift-localize-cli
```

## Use as a Swift package dependency

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "<repository-url>", from: "0.1.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "swift-localize", package: "swift-localize")
        ]
    )
]
```

Then call it from your code:

```swift
import swift_localize

let config = try LocalizerConfig.load(from: "./localize.json")
let localizer = Localizer(config: config)
try await localizer.run()
```

## Configuration Reference

| Key | Required | Description |
| --- | --- | --- |
| `credentialsPath` | Yes | Path to Google service account JSON key file. |
| `spreadsheetId` | Yes | Spreadsheet ID from the Google Sheets URL. |
| `outputDirectory` | Yes | Directory for `.xcstrings` snapshots and XLIFF files. |
| `sourceLanguage` | Yes | BCP-47 language code used as source language (for example `de`). |
| `xcodeProjectPath` | Optional | Path to `.xcodeproj` for `xcodebuild` export/import flow. |
| `xcodeWorkspacePath` | Optional | Path to `.xcworkspace` for `xcodebuild` flow. |
| `xcodeScheme` | Conditionally required | Required when `xcodeWorkspacePath` is set. |

Rules:
- Set either `xcodeProjectPath` or `xcodeWorkspacePath`.
- Do not set both at the same time.
- If using workspace mode, set `xcodeScheme`.

## Development

Run tests:

```sh
swift test
```
