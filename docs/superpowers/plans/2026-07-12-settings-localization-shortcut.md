# Settings Localization and Entry Points Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Localize the existing Settings content, add Command-P as an additional Settings shortcut, and add a Settings entry at the bottom of the main sidebar without changing the Settings window title.

**Architecture:** Keep the feature entirely in SwiftUI. Reuse `AppPreferences` and `AppLanguage`, register Command-P once in the application command hierarchy, and use `SettingsLink` for both the menu command and the visible sidebar entry so both routes open the existing Settings scene.

**Tech Stack:** Swift 5, SwiftUI for macOS 14, Observation, XCTest

---

### Task 1: Localize Settings content

**Files:**
- Modify: `CapricornTests/CapricornTests.swift:84`
- Modify: `Capricorn/Support/Localization/CommonLocalization.swift:160`
- Modify: `Capricorn/App/AppPreferences.swift:69`

- [ ] **Step 1: Write the failing localization test**

Add this test beside `testGitHubRepositoryIntroductionIsLocalized()`:

```swift
func testSettingsContentIsLocalized() {
    let expectedTranslations = [
        "Settings": "设置",
        "Include serials in reports": "报告中包含序列号",
        "Use Tab to switch feature pages": "使用 Tab 切换功能页面",
        "Automatic detection": "自动检测",
        "Choose…": "选择…",
        "Automatic": "自动",
        "The selected smartctl path is not executable.": "所选 smartctl 路径不可执行。",
        "Control-Tab and Control-Shift-Tab always switch feature pages. Disable plain Tab switching to restore standard keyboard focus traversal.": "Control-Tab 和 Control-Shift-Tab 始终用于切换功能页面。关闭普通 Tab 切换后，可恢复标准键盘焦点遍历。",
        "Choose": "选择",
        "Choose the smartctl executable.": "选择 smartctl 可执行文件。",
        "Open Settings": "打开设置"
    ]

    for (key, expected) in expectedTranslations {
        XCTAssertEqual(AppLanguage.simplifiedChinese.t(key), expected, key)
        XCTAssertEqual(AppLanguage.english.t(key), key, key)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```sh
xcodebuild test -quiet \
  -project Capricorn.xcodeproj \
  -scheme Capricorn \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:CapricornTests/CapricornTests/testSettingsContentIsLocalized
```

Expected: FAIL because the new keys currently fall back to their English values.

- [ ] **Step 3: Add the Simplified Chinese strings**

Add the following entries to `AppLanguage.zhHans`:

```swift
"Settings": "设置",
"Include serials in reports": "报告中包含序列号",
"Use Tab to switch feature pages": "使用 Tab 切换功能页面",
"Automatic detection": "自动检测",
"Choose…": "选择…",
"Automatic": "自动",
"The selected smartctl path is not executable.": "所选 smartctl 路径不可执行。",
"Control-Tab and Control-Shift-Tab always switch feature pages. Disable plain Tab switching to restore standard keyboard focus traversal.": "Control-Tab 和 Control-Shift-Tab 始终用于切换功能页面。关闭普通 Tab 切换后，可恢复标准键盘焦点遍历。",
"Choose": "选择",
"Choose the smartctl executable.": "选择 smartctl 可执行文件。",
"Open Settings": "打开设置",
```

- [ ] **Step 4: Route Settings view text through `AppLanguage`**

Add a computed language property and replace the Settings strings:

```swift
private var language: AppLanguage {
    preferences.language
}
```

Use `language.t(...)` for the picker, toggles, smartctl controls, warning, navigation explanation, `NSOpenPanel.prompt`, and `NSOpenPanel.message`. Apply the selected locale to the form:

```swift
.environment(\.locale, Locale(identifier: language.localeIdentifier))
```

Do not add a navigation title or change the Settings scene title.

- [ ] **Step 5: Run the localization test**

Run the command from Step 2.

Expected: PASS.

### Task 2: Add Command-P Settings command

**Files:**
- Modify: `CapricornTests/CapricornTests.swift:405`
- Modify: `Capricorn/Domain/DITModels.swift:434`
- Modify: `Capricorn/App/CapricornApp.swift:35`

- [ ] **Step 1: Write the failing shortcut test**

Add beside `testRefreshCommandShortcutUsesCommandR()`:

```swift
func testSettingsShortcutUsesCommandP() {
    XCTAssertEqual(AppCommandShortcut.settings.key, "p")
    XCTAssertTrue(AppCommandShortcut.settings.modifiers.contains(.command))
    XCTAssertEqual(AppCommandShortcut.settingsKeyEquivalent, KeyEquivalent("p"))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```sh
xcodebuild test -quiet \
  -project Capricorn.xcodeproj \
  -scheme Capricorn \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:CapricornTests/CapricornTests/testSettingsShortcutUsesCommandP
```

Expected: build failure because `AppCommandShortcut.settings` and `settingsKeyEquivalent` do not exist.

- [ ] **Step 3: Add the shortcut definition**

Add to `AppCommandShortcut`:

```swift
static let settings = (key: "p", modifiers: EventModifiers.command)
static let settingsKeyEquivalent = KeyEquivalent("p")
```

- [ ] **Step 4: Register the Settings command once**

Insert a `SettingsLink` after the system application Settings group:

```swift
CommandGroup(after: .appSettings) {
    SettingsLink {
        Text(language.t("Settings"))
    }
    .keyboardShortcut(
        AppCommandShortcut.settingsKeyEquivalent,
        modifiers: AppCommandShortcut.settings.modifiers
    )
}
```

Keep the existing command groups and the system Command-Comma command intact.

- [ ] **Step 5: Run the shortcut test**

Run the command from Step 2.

Expected: PASS.

### Task 3: Add the bottom-left Settings entry

**Files:**
- Modify: `Capricorn/App/ContentView.swift:146`

- [ ] **Step 1: Add the sidebar SettingsLink**

At the bottom of the existing sidebar footer, after the status row, add:

```swift
Divider()

SettingsLink {
    HStack(spacing: 8) {
        Label(language.t("Settings"), systemImage: "gearshape")
            .font(.caption.weight(.semibold))
        Spacer(minLength: 8)
        Text("⌘P")
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
}
.buttonStyle(.plain)
.foregroundStyle(.secondary)
.help(language.t("Open Settings"))
.accessibilityLabel(language.t("Open Settings"))
```

Do not attach another `.keyboardShortcut`; Command-P is registered only in the application command hierarchy.

- [ ] **Step 2: Build the application**

Run:

```sh
xcodebuild build -quiet \
  -project Capricorn.xcodeproj \
  -scheme Capricorn \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

### Task 4: Complete verification

**Files:**
- Verify: all modified source and test files

- [ ] **Step 1: Run the complete test suite**

```sh
xcodebuild test -quiet \
  -project Capricorn.xcodeproj \
  -scheme Capricorn \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Expected: exit code 0 with no failing tests.

- [ ] **Step 2: Run strict concurrency verification**

```sh
xcodebuild build -quiet \
  -project Capricorn.xcodeproj \
  -scheme Capricorn \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData/StrictConcurrency \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_STRICT_CONCURRENCY=complete \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
```

Expected: exit code 0.

- [ ] **Step 3: Run Swift 6 compatibility verification**

```sh
xcodebuild build -quiet \
  -project Capricorn.xcodeproj \
  -scheme Capricorn \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData/Swift6 \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_VERSION=6
```

Expected: exit code 0.

- [ ] **Step 4: Check the final diff**

```sh
git diff --check
git status -sb
```

Expected: no whitespace errors and only the approved Settings-related files plus this plan are modified.
