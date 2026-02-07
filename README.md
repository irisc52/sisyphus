# Sisyphus - Anti-Doomscrolling Extension

A Chrome/Edge extension that tracks scroll time on selected domains and applies **graduated psychological interventions** to discourage doomscrolling. Uses the "boiling frog" approach - interventions escalate gradually over weeks so users don't immediately uninstall.

## Features

### Core Functionality
- **Domain tracking** – Add domains via popup to track scroll time
- **24-hour reset** – Scroll time resets every 24 hours per domain
- **Persistent storage** – Uses `chrome.storage.sync` for cross-device sync
- **Grayscale progression** – Screen slowly turns grayscale as you scroll
- **Scroll friction** – Scrolling becomes harder the longer you stay

### Graduated Intervention System (Boiling Frog 🐸)

The extension uses 5 escalation levels that increase based on:
1. **Time since install** (weeks)
2. **Minutes scrolled today** on each domain

#### Level 0: OBSERVE (Week 1)
- Just tracks time, no interventions
- Lets you see tracking works without disruption

#### Level 1: GENTLE (Week 2+, after 20min)
- Grayscale filter (100%)
- Life clock showing time wasted

#### Level 2: MODERATE (Week 3+, after 30min)
- + Blur effect (2px)
- + Vignette (tunnel vision)
- + Occasional regret quotes

#### Level 3: AGGRESSIVE (Week 4+, after 35min)
- + Reduced contrast & brightness
- + Stronger blur (4px)
- + Click delays (1.5 seconds)
- + Dopamine counter (shows scroll count)
- + Opportunity cost messages
- + Fake loading screens

#### Level 4: NUCLEAR (Week 4+, after 50min)
- Full-screen break overlay
- 10-second countdown before override
- Suggests closing the tab

## Installation

### Chrome / Edge

1. Download or clone this repository
2. Open `chrome://extensions` (or `edge://extensions`)
3. Enable **Developer mode** (toggle in top right)
4. Click **Load unpacked**
5. Select the folder containing these files

### Files Required

```
sisyphus/
├── manifest.json           # Extension manifest (MV3)
├── background.js           # Service worker, intervention logic
├── content.js              # Page injection, orchestration
├── interventions.js        # All psychological effects
├── popup.html              # Extension popup UI
├── popup.css               # Popup styles
├── popup.js                # Domain management
└── README.md               # This file
```

## How It Works

### 1. Domain Selection (popup.html/js)
- User adds domains to track (e.g., `twitter.com`, `reddit.com`)
- Domains stored in `chrome.storage.sync`

### 2. Time Tracking (content.js → background.js)
- Content script checks if current domain is tracked
- If tracked, reports time to background every 5 seconds
- Background applies 24-hour reset logic

### 3. Intervention Calculation (background.js)
- Content script asks: "What intervention level should I apply?"
- Background calculates based on:
  - Days since install
  - Minutes scrolled today
- Returns intervention level (0-4)

### 4. Effect Application (content.js + interventions.js)
- Content script calls appropriate effects from `SisyphusEffects`
- Effects stack as levels increase
- All effects removed when user leaves page or switches tabs

## Intervention Timing (Boiling Frog Schedule)

| Week | Minutes | Level | Effects |
|------|---------|-------|---------|
| 1 | Any | 0 | None (just tracking) |
| 2 | 0-20 | 0 | None |
| 2 | 20+ | 1 | Grayscale + Life Clock |
| 3 | 0-15 | 0 | None |
| 3 | 15-30 | 1 | Gentle |
| 3 | 30+ | 2 | Moderate (blur, vignette, quotes) |
| 4+ | 0-10 | 0 | None |
| 4+ | 10-20 | 1 | Gentle |
| 4+ | 20-35 | 2 | Moderate |
| 4+ | 35-50 | 3 | Aggressive (click delay, counters) |
| 4+ | 50+ | 4 | Nuclear (break overlay) |

## Development

### Testing Interventions

To test without waiting weeks:

1. Open Chrome DevTools → Application → Storage → chrome.storage.sync
2. Set `installDate` to a past date:
```javascript
// In console:
chrome.storage.sync.set({ installDate: Date.now() - (30 * 24 * 60 * 60 * 1000) });
// Sets install date to 30 days ago
```

3. Add a domain and scroll to accumulate time

### Debugging

- **Background logs**: `chrome-extension://[your-id]/_generated_background_page.html`
- **Content logs**: Open DevTools on any tracked page
- **Storage inspection**: DevTools → Application → Storage

### Key Functions

**interventions.js:**
- `SisyphusEffects.applyGrayscale(intensity)` - Grayscale filter
- `SisyphusEffects.showLifeClock(minutes)` - Time wasted counter
- `SisyphusEffects.showRegretQuote()` - Random intervention message
- `SisyphusEffects.showBreakOverlay(minutes)` - Nuclear option
- `SisyphusEffects.removeAllEffects()` - Clean up

**background.js:**
- `getInterventionLevel(domain)` - Calculate current level
- `updateScrollTime(domain, ms)` - Update time tracking
- `getScrollDataWithReset()` - Get data with 24h reset

## Customization

### Adjust Intervention Thresholds

Edit `background.js`, function `getInterventionLevel()`:

```javascript
// Week 4+: Full graduated intervention
if (minutes < 10) return InterventionLevel.OBSERVE;
if (minutes < 20) return InterventionLevel.GENTLE;     // ← Change these
if (minutes < 35) return InterventionLevel.MODERATE;   // ← numbers to
if (minutes < 50) return InterventionLevel.AGGRESSIVE; // ← adjust timing
return InterventionLevel.NUCLEAR;
```

### Disable Specific Effects

Edit `content.js`, function `applyInterventionLevel()`:

```javascript
case 3: // AGGRESSIVE
  effects.reduceContrast();
  effects.applyBlur(4);
  // effects.addClickDelay(1500);  // ← Comment out to disable
  effects.showLifeClock(minutes);
  // effects.showDopamineCounter();  // ← Comment out to disable
  break;
```

### Add New Effects

1. Add function to `interventions.js`:
```javascript
showMyNewEffect() {
  // Your effect code
}
```

2. Call it in `content.js` at appropriate level:
```javascript
case 2: // MODERATE
  // ... existing effects
  effects.showMyNewEffect();
  break;
```

## Privacy

- All data stored locally in browser (no external servers)
- `chrome.storage.sync` syncs across your logged-in Chrome browsers
- No tracking, analytics, or external connections
- Open source - audit the code yourself

## License

MIT License - Do whatever you want with it

## Contributing

This is an experimental psychological intervention tool. If you have ideas for:
- More effective intervention techniques
- Better escalation timing
- Additional psychological effects
- Ways to prevent circumvention

Feel free to fork and experiment!

## Credits

Inspired by the psychological concept of the "boiling frog" - gradual changes are more acceptable than sudden ones. 

Named after Sisyphus, condemned to push a boulder uphill forever, only for it to roll back down - much like the repetitive nature of doomscrolling.
