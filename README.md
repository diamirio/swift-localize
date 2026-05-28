# swift-localize

`swift-localize` syncs translations from Google Sheets directly into your Xcode project's `.xcstrings` String Catalogs.

It is the Swift Package successor to the deprecated [`fastlane-plugin-localize`](https://github.com/diamirio/fastlane-plugin-localize) Ruby plugin: same Google Sheets workflow, same service-account auth, but emits modern String Catalogs (`.xcstrings`) instead of `.strings` + `.stringsdict`.

Google Sheets is the source of truth: new keys appear in the app, renamed keys replace old ones, and removed keys are deleted from the catalog.

## Features

- One `.xcstrings` String Catalog per Google Sheet tab.
- Plural variations (`one|...`, `other|...`, …) are mapped to xcstrings plural variations — no more `stringsdict`.
- Cross-platform format placeholders (`%s`, `%1s`, `%2s`) are remapped to Apple form (`%@`, `%1$@`, `%2$@`).
- Optional tab allow-list and configurable identifier column header (for re-using a sheet across platforms).
- Diff logging per tab: added / removed / updated keys.
- Pure Swift, no fastlane / Ruby dependency.

## Requirements

- macOS 14+
- Swift 6.2 toolchain (or compatible with this package)
- A Google Cloud service account with access to the Google Sheets API

## How It Works

1. Authenticate with Google using a service account JSON key (PKCS#8 RSA, signed JWT → OAuth2 token).
2. Read spreadsheet tab metadata and (optionally) filter by `tabs`.
3. For each tab, fetch values, parse rows, transform placeholders / plurals.
4. Write the result to `<localizationPath>/<tabName>.xcstrings`, overwriting in place.

Empty tabs (no parseable rows) remove an existing catalog file rather than leaving a stale one behind.

## Spreadsheet Format

Each sheet tab maps to one `.xcstrings` file. The header row must contain:

- An **identifier column** (default `Identifier iOS`, configurable).
- One column per BCP-47 short language code (`de`, `en`, `fr`, …) — long codes like `en-US` are ignored.
- A **`Kommentar`** column. Everything to the right of `Kommentar` is ignored.

Example:

| Identifier iOS | de | en | fr | Kommentar | Identifier Android |
|---|---|---|---|---|---|
| welcome_title | Willkommen | Welcome | Bienvenue | Main screen title | welcome_title |
| button_ok | OK | OK | OK | | btn_ok |

### Row filtering

- Rows where the identifier is empty, `NR`, `TBD`, or starts with `//` are skipped.
- Individual language cells that are empty, `NR`, or `TBD` are omitted for that language only.

### Placeholder remapping

Authors write platform-neutral placeholders in the sheet; the CLI rewrites them on import:

| Sheet value | Written to `.xcstrings` |
|---|---|
| `Hello %s` | `Hello %@` |
| `Mario ate a %2s %1s` | `Mario ate a %2$@ %1$@` |
| `Pi: %.2f`, `Count: %d`, `Name: %@` | unchanged |

### Plurals

Plural cells follow the legacy plugin's format:

```
one|%d artist
other|%d artists
```

Categories accepted (case-insensitive): `zero`, `one`, `two`, `few`, `many`, `other`. The `other` category is required; cells missing it are written as a single string. Plural cells become proper xcstrings plural variations:

```json
"artists.count": {
  "localizations": {
    "en": {
      "variations": {
        "plural": {
          "one":   { "stringUnit": { "state": "translated", "value": "%d artist" } },
          "other": { "stringUnit": { "state": "translated", "value": "%d artists" } }
        }
      }
    }
  }
}
```

## Setup

### 1) Create Google service account credentials

1. Open the Google Cloud Console and create/select a project.
2. Enable the **Google Sheets API**.
3. Create a **service account**.
4. Create and download a **JSON key** file.
5. Share your target Google Sheet with the service account email (Viewer permission is enough).

Save the JSON key locally, for example as `./credentials/google_drive_credentials.json`.

### 2) Create `localize.json`

Place it next to your `.xcodeproj`:

```json
{
  "credentialsPath":  "./credentials/google_drive_credentials.json",
  "spreadsheetId":    "YOUR_SPREADSHEET_ID",
  "localizationPath": "./MyApp",
  "sourceLanguage":   "de",
  "tabs":             ["Common", "Onboarding"],
  "identifierColumn": "Identifier iOS"
}
```

All paths are resolved relative to the config file's location, so the CLI can be invoked from any working directory.

## Configuration Reference

| Key | Required | Description |
| --- | --- | --- |
| `credentialsPath` | Yes | Path to Google service account JSON key file. |
| `spreadsheetId` | Yes | Spreadsheet ID from the Google Sheets URL. |
| `localizationPath` | Yes | Directory inside your Xcode project where `.xcstrings` files live. Each tab is written as `<localizationPath>/<tabName>.xcstrings`. |
| `sourceLanguage` | Yes | BCP-47 language code used as `sourceLanguage` in every catalog (e.g. `de`). |
| `tabs` | No | Allow-list of sheet tab titles. Omit or use `[]` to import all tabs. Tabs missing from the spreadsheet log a warning. |
| `identifierColumn` | No | Header name of the identifier column. Defaults to `Identifier iOS`. Useful for sheets shared with Android/Web (`Identifier Android`, `Identifier Web`). |

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

## Migrating from `fastlane-plugin-localize`

`swift-localize` keeps the same Google Sheet conventions ("Sheet Language") and replaces the rest:

| Old fastlane option | New behavior |
|---|---|
| `service_account_path` | `credentialsPath` |
| `sheet_id` | `spreadsheetId` |
| `localization_path` | `localizationPath` |
| `tabs` | `tabs` (allow-list, optional) |
| `identifier_name` | `identifierColumn` (optional, default `Identifier iOS`) |
| `language_titles` | Auto-detected from header row (any valid ISO short code). |
| `default_language` | Removed — xcstrings handles fallback to `sourceLanguage` at runtime. |
| `base_language` | Removed — `.xcstrings` is a single file; the `sourceLanguage` field replaces `Base.lproj`. |
| `comment_example_language` | Removed — the `Kommentar` column is written verbatim as the entry's `comment`. |
| `support_objc`, `code_generation_path`, `support_spm` | Removed — Xcode 15+ auto-generates symbols from `.xcstrings`. |
| `platform` (android/web) | Removed — Swift-only scope. |
| `.strings` + `.stringsdict` output | Replaced with `.xcstrings` (plurals → `variations.plural`). |

## Development

Run tests (requires full Xcode for Swift Testing macro plugins):

```sh
swift test
```
