# Add Dashboard to Xcode iOS App

Your React dashboard (from `uiux/`) can run inside the Sisyphus iOS app via a WKWebView. Follow these steps:

## 1. Build the dashboard

From the project root:

```bash
cd uiux
npm run build:ios
```

This builds the dashboard and copies the output to:

```
extension/Sisyphus/Shared (App)/Resources/Dashboard/
├── dashboard.html
└── assets/
    ├── dashboard-xxx.js
    └── dashboard-xxx.css
```

## 2. Verify files in Xcode

Open the project in Xcode:

```
extension/Sisyphus/Sisyphus.xcodeproj
```

In the **Project Navigator**, under **Shared (App) → Resources**, you should see the **Dashboard** folder containing:
- `dashboard.html`
- `assets/` (with .js and .css files)

If the folder is missing, right‑click **Resources** → **Add Files to "Sisyphus"** → select the `Dashboard` folder → ensure **"Sisyphus (iOS)"** is checked.

## 3. Run the app

1. Select the **Sisyphus (iOS)** scheme.
2. Choose your iPhone as the run destination.
3. Click **Run** (⌘R).

The app will show the dashboard as the main screen.

## 4. When you change the dashboard

1. Edit files in `uiux/src/`.
2. Run `npm run build:ios` again from `uiux/`.
3. Rebuild in Xcode.

## Note: chrome.storage in the app

The dashboard uses `chrome.storage` when it runs as a browser extension. Inside the iOS app’s WKWebView, `chrome.storage` is not available, so the dashboard falls back to mock data for development. To use real data in the app, you’d need a bridge between the extension and the app.
