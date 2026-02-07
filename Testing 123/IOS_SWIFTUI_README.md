# Sisyphus iOS App — SwiftUI

The iOS app UI has been rewritten in **SwiftUI** for a native, iOS-friendly experience. The app now provides:

## Features

- **Dashboard** — Stats cards (today's scroll, time limit, tracked sites), per-domain scroll time, weekly progress placeholder, and tips
- **Domains** — Add/remove tracked domains with a clean list UI and swipe-to-delete
- **Settings** — Daily scroll limit picker (5 min to 2 hours, or unlimited), Safari extension help link
- **Native iOS design** — System fonts, SF Symbols, dark/light mode support, haptic-ready

## How to Run

1. Open `Testing 123.xcodeproj` in Xcode
2. Select the **Testing 123 (iOS)** scheme
3. Choose your iPhone or simulator as the run destination
4. Build and run (⌘R)

The main app now uses SwiftUI instead of the previous web-based UI. The Safari extension (popup, content script, background) still uses HTML/JS and runs inside Safari when enabled.

## Data Sync with Extension

The SwiftUI app stores data in **UserDefaults** locally. The Safari extension uses **browser.storage** in its own context. Right now these are separate. To sync data between the app and extension:

1. Add **App Groups** capability to both the app and extension targets
2. Use `UserDefaults(suiteName: "group.com.yourteam.sisyphus")` for shared storage
3. Update `SafariWebExtensionHandler.swift` to respond to `sendNativeMessage` requests from the extension with the shared config
4. Update the extension's `background.js` to request config from the native side on startup

## Files Added

- `Shared (App)/SisyphusData.swift` — Data model and persistence
- `Shared (App)/SisyphusContentView.swift` — Main TabView
- `Shared (App)/DashboardView.swift` — Dashboard screen
- `Shared (App)/DomainListView.swift` — Domain management
- `Shared (App)/SettingsView.swift` — Settings screen

## Extension Setup

To use Sisyphus on iOS Safari:

1. Build and run the app on your device
2. Open **Settings → Safari → Extensions**
3. Enable **Sisyphus**
4. The extension will track scroll time on domains you add in the app (once sync is wired up) or in the extension popup
