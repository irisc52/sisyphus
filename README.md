# Sisyphus

Anti-doomscrolling web extension. Tracks scroll time on selected domains with a 24-hour reset.

## Features

- **Domain tracking/selection** – Add or remove domains to track via the popup
- **Persistent storage** – Uses `chrome.storage.sync` for cross-session and cross-device sync
- **24-hour reset** – Scroll time resets every 24 hours per domain
- **Content script injection** – Runs on all URLs; tracking is active only on selected domains

## Chrome / Edge Setup

1. Open `chrome://extensions` (or `edge://extensions`)
2. Enable **Developer mode**
3. Click **Load unpacked**
4. Select the `sisyphus` folder

## iOS Safari Setup

Safari Web Extensions on iOS require wrapping in an Xcode project. See **[IOS-XCODE-GUIDE.md](IOS-XCODE-GUIDE.md)** for step-by-step instructions.

Quick path:
1. **Xcode → File → New → Project** → **Safari Extension App**
2. Replace the template extension files with files from `extension/`
3. **Run** (▶️) with your iPhone as the destination
4. On iPhone: **Settings → VPN & Device Management** → Trust → **Safari → Extensions** → Enable Sisyphus

## Project Structure

```
sisyphus/
├── manifest.json   # Extension manifest (MV3)
├── popup.html      # Popup UI
├── popup.css       # Popup styles
├── popup.js        # Domain selection, storage, 24h reset
├── background.js   # Service worker, scroll time updates
├── content.js      # Injected on pages, tracks scroll time
└── README.md
```

## How It Works

1. **Popup** – Add domains to track (e.g. `twitter.com`, `reddit.com`). Data is stored in `chrome.storage.sync`.
2. **Content script** – Loaded on all pages. Checks if the current domain is tracked; if so, measures scroll time and reports to the background every 5 seconds.
3. **Background** – Receives scroll updates, applies 24-hour reset logic, and writes to `chrome.storage.sync`.
4. **24-hour reset** – Each domain stores `lastResetTimestamp`. When `Date.now() - lastResetTimestamp >= 24h`, total time resets to 0.

## Icons (Optional)

To add icons, create `icons/` with `icon16.png`, `icon48.png`, `icon128.png` and add to `manifest.json`:

```json
"action": {
  "default_popup": "popup.html",
  "default_icon": {
    "16": "icons/icon16.png",
    "48": "icons/icon48.png",
    "128": "icons/icon128.png"
  }
},
"icons": {
  "16": "icons/icon16.png",
  "48": "icons/icon48.png",
  "128": "icons/icon128.png"
}
```
