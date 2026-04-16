# swift-localize

`swift-localize` syncs translations from Google Sheets directly into your Xcode project's `.xcstrings` string catalogs.

Google Sheets is the source of truth: new keys appear in the app, renamed keys replace old ones, and removed keys are deleted from the catalog.

## Requirements

- macOS 14+
- Swift 6.2 toolchain (or compatible with this package)
- A Google Cloud service account with access to Google Sheets API

## How It Works

1. Authenticate with Google using a service account JSON key.
2. Read spreadsheet tabs and values.
3. Parse translation rows (`key` column + one column per language).
4. For each tab, write translations directly into the mapped `.xcstrings` file inside your Xcode project.
   - Tabs not listed in `stringCatalogs` fall back to writing into `outputDirectory`.

## Spreadsheet Format

Each sheet tab maps to one `.xcstrings` file. Rows follow this convention:

| key | de | en | fr |
|---|---|---|---|
| welcome_title | Willkommen | Welcome | Bienvenue |
| button_ok | OK | OK | OK |

The first column is the localization key. Subsequent columns are BCP-47 language codes.

## Setup

### 1) Create Google service account credentials

1. Open Google Cloud Console and create/select a project.
2. Enable the Google Sheets API.
3. Create a service account.
4. Create and download a JSON key file.
5. Share your target Google Sheet with the service account email (Viewer permission is sufficient).

Save the JSON key file locally, for example as `./credentials/google_drive_credentials.json`.

### 2) Create `localize.json`

Create a config file — typically placed next to your `.xcodeproj`:

```json
{
  "credentialsPath":  "./credentials/google_drive_credentials.json",
  "spreadsheetId":    "YOUR_SPREADSHEET_ID",
  "localizationPath": "./MyApp",
  "sourceLanguage":   "de"
}
```

All paths are resolved relative to the config file's location. Each sheet tab is written as `<localizationPath>/<tabName>.xcstrings` directly into your Xcode project folder.

## Run as CLI

From the package root:

```sh
swift run swift-localize-cli --config /path/to/localize.json
```

Default (looks for `./localize.json` in the current directory):

```sh
swift run swift-localize-cli
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
| `localizationPath` | Yes | Directory inside your Xcode project where `.xcstrings` files live. Each tab is written as `<localizationPath>/<tabName>.xcstrings`. |
| `sourceLanguage` | Yes | BCP-47 language code used as source language (e.g. `de`). |

## Development

Run tests:

```sh
swift test
```
