# Running Sisyphus on Your iPhone with Xcode

Safari Web Extensions on iOS run inside a companion app. You need Xcode to build and deploy to your phone.

## Prerequisites

- Mac with Xcode (free from App Store)
- Apple ID (free)
- iPhone connected via USB

---

## Option A: Create New Safari Extension App (Recommended)

This creates a fresh Xcode project with the Safari extension template.

### Step 1: Create the project in Xcode

1. Open **Xcode**
2. **File → New → Project**
3. Under **Multiplatform**, select **Safari Extension App**
4. Click **Next**
5. Configure:
   - **Product Name**: `Sisyphus`
   - **Team**: your Apple ID
   - **Organization Identifier**: e.g. `com.yourname`
   - **Bundle Identifier**: will be `com.yourname.Sisyphus`
6. Uncheck **Include Tests**
7. Choose a folder and click **Create**

### Step 2: Replace the extension files

Xcode will create a project with a placeholder Safari extension. Replace it with Sisyphus:

1. In the project navigator (left sidebar), find the **Safari Extension** folder — often named `SisyphusExtension` or similar
2. Right‑click that folder → **Show in Finder**
3. Delete the template files (manifest.json, popup.html, etc.)
4. Copy these files from `sisyphus/extension/` into that folder:
   - `manifest.json`
   - `popup.html`
   - `popup.css`
   - `popup.js`
   - `background.js`
   - `content.js`

### Step 3: Run on your iPhone

1. Connect your iPhone via USB
2. In Xcode, set **Run destination** (top bar) to your iPhone
3. Click **Run** (▶️) or press **⌘R**
4. On the iPhone: **Settings → General → VPN & Device Management** → trust the developer certificate
5. Open **Safari** on the iPhone
6. **Settings (gear) → Extensions** → enable **Sisyphus**

---

## Option B: Use the Safari Web Extension Converter

If the converter accepts your manifest, it can generate the Xcode project.

### Step 1: Open Terminal

```bash
cd /Users/irista/Desktop/scroll/sisyphus
```

### Step 2: Run the converter

```bash
xcrun safari-web-extension-converter extension \
  --app-name "Sisyphus" \
  --bundle-identifier "com.sisyphus.antidoomscrolling"
```

If you get **"Unable to parse manifest.json"**, the converter may not support Manifest V3. Use Option A instead.

### Step 3: Open and run the project

1. Xcode will open the generated project (or open the `.xcodeproj` in the `extension` folder)
2. Select your iPhone as the run destination
3. Click **Run** (▶️)
4. Trust the certificate on your iPhone and enable the extension in Safari

---

## Troubleshooting

### "Untrusted Developer" on iPhone
- **Settings → General → VPN & Device Management** → tap your developer certificate → **Trust**

### Extension doesn’t appear in Safari
- **Safari → Settings (gear) → Extensions** → turn on Sisyphus

### Build fails with signing errors
- Select the project in Xcode → **Signing & Capabilities**
- Choose your **Team**
- Turn on **Automatically manage signing**

### "Unable to find popup.html"
- Ensure `popup.html`, `manifest.json`, and other extension files are in the Safari Extension target folder
- Select the extension target → **Build Phases → Copy Bundle Resources** → ensure those files are listed

### Extension works in Simulator but not on device
- Safari Web Extensions on iOS run only on real devices
- Make sure the run destination is your iPhone, not Simulator
