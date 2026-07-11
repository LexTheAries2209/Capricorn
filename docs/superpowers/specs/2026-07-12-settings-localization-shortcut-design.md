# Settings Localization and Entry Points Design

## Goal

Make the existing macOS Settings scene follow Capricorn's in-app language selection, add Command-P as an additional Settings shortcut, and add a visible Settings entry at the bottom of the main sidebar.

The Settings window title remains unchanged. The system-provided Command-Comma shortcut remains available.

## Architecture

The implementation remains entirely in SwiftUI:

- `CapricornSettingsView` renders localized labels using the current `AppLanguage` from `AppPreferences`.
- `CapricornApp` adds a localized `SettingsLink` command with Command-P.
- `ContentView` adds a localized `SettingsLink` to the bottom of the existing sidebar footer.
- `AppCommandShortcut` owns the Command-P key equivalent and modifiers alongside the existing application shortcuts.
- `AppLanguage` continues to provide translations through the existing `language.t(...)` behavior.

No new window coordinator, global notification, responder-chain hook, or AppKit settings bridge is introduced.

## Settings Content

When the application language is Simplified Chinese, the following content is translated:

- Language
- Show virtual disks
- Include serial numbers in reports
- Use Tab to switch feature pages
- Automatic smartctl detection
- Choose and restore-automatic buttons
- Invalid smartctl path warning
- Keyboard navigation explanation
- smartctl file-picker prompt and message

Changing the language updates the Settings content reactively through the shared observable `AppPreferences`. The window title remains the system-generated Capricorn Settings title.

## Commands and Sidebar

The application command hierarchy adds a Settings entry using `SettingsLink` and Command-P. It supplements rather than replaces the standard macOS Command-Comma Settings command.

The sidebar footer adds a bottom-most Settings row with:

- `gearshape` system image
- localized Settings label
- visible Command-P shortcut hint

Both entry points open the existing singleton Settings scene.

## Error Handling

The smartctl executable picker keeps its current behavior. Its prompt and explanatory message use the selected application language. Invalid executable paths continue to show the existing warning, now localized.

## Testing

Automated tests cover:

- English and Simplified Chinese Settings strings.
- Command-P key and modifier definitions.
- Preservation of the existing Command-Comma system Settings path by using `SettingsLink` rather than replacing the application Settings command.

Verification includes the complete test suite, strict concurrency build with warnings treated as errors, Swift 6 compatibility build, and `git diff --check`.

## Scope Boundaries

This change does not alter preference keys, persistence, Settings window sizing, Settings window title, application versioning, release flow, or unrelated sidebar behavior.
