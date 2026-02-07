/**
 * Sisyphus - Anti-Doomscrolling Extension
 * Background service worker - handles storage, 24-hour reset logic, and domain matching
 * Syncs with native app via sendNativeMessage for live dashboard updates
 */

const STORAGE_KEYS = {
  TRACKED_DOMAINS: 'trackedDomains',
  SCROLL_DATA: 'scrollData',
  SCROLL_LIMIT_MS: 'scrollLimitMs',
  SETTINGS: 'settings'
};

const HOURS_24_MS = 24 * 60 * 60 * 1000;
const NATIVE_APP = 'ICKI.Testing-123';
const SYNC_INTERVAL_MS = 5000;

/**
 * Get the current domain's storage key (normalized)
 */
function getDomainKey(url) {
  try {
    const urlObj = new URL(url);
    return urlObj.hostname.replace(/^www\./, '');
  } catch {
    return null;
  }
}

/**
 * Check if timestamp has exceeded 24 hours (needs reset)
 */
function shouldReset(timestamp) {
  return Date.now() - timestamp >= HOURS_24_MS;
}

/**
 * Get scroll data with 24-hour reset logic applied
 */
async function getScrollDataWithReset() {
  const result = await chrome.storage.sync.get([STORAGE_KEYS.SCROLL_DATA, STORAGE_KEYS.TRACKED_DOMAINS]);
  let scrollData = result[STORAGE_KEYS.SCROLL_DATA] || {};
  const trackedDomains = result[STORAGE_KEYS.TRACKED_DOMAINS] || [];

  let changed = false;
  for (const domain of Object.keys(scrollData)) {
    const entry = scrollData[domain];
    if (entry && shouldReset(entry.lastResetTimestamp)) {
      scrollData[domain] = {
        totalMs: 0,
        lastResetTimestamp: Date.now()
      };
      changed = true;
    }
  }

  if (changed) {
    await chrome.storage.sync.set({ [STORAGE_KEYS.SCROLL_DATA]: scrollData });
  }

  return scrollData;
}

/**
 * Update scroll time for a domain (with 24-hour reset check)
 */
async function updateScrollTime(domain, additionalMs) {
  const result = await chrome.storage.sync.get([STORAGE_KEYS.SCROLL_DATA]);
  let scrollData = result[STORAGE_KEYS.SCROLL_DATA] || {};
  const entry = scrollData[domain];

  const now = Date.now();
  let newEntry;

  if (!entry || shouldReset(entry.lastResetTimestamp)) {
    newEntry = {
      totalMs: additionalMs,
      lastResetTimestamp: now
    };
  } else {
    newEntry = {
      totalMs: entry.totalMs + additionalMs,
      lastResetTimestamp: entry.lastResetTimestamp
    };
  }

  scrollData[domain] = newEntry;
  await chrome.storage.sync.set({ [STORAGE_KEYS.SCROLL_DATA]: scrollData });
  return newEntry;
}

/**
 * Message handler from content script
 */
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'UPDATE_SCROLL_TIME') {
    const domain = getDomainKey(sender.url || message.url);
    if (domain) {
      updateScrollTime(domain, message.ms).then(sendResponse);
      return true; // Keep channel open for async response
    }
  }

  if (message.type === 'GET_TRACKED_DOMAINS') {
    chrome.storage.sync.get([STORAGE_KEYS.TRACKED_DOMAINS])
      .then(r => sendResponse({ domains: r[STORAGE_KEYS.TRACKED_DOMAINS] || [] }));
    return true;
  }

  if (message.type === 'IS_DOMAIN_TRACKED') {
    chrome.storage.sync.get([STORAGE_KEYS.TRACKED_DOMAINS])
      .then(r => {
        const domains = r[STORAGE_KEYS.TRACKED_DOMAINS] || [];
        const key = getDomainKey(message.url);
        sendResponse({ tracked: key ? domains.includes(key) : false });
      });
    return true;
  }
});

// Sync extension data to native app so SwiftUI dashboard stays live
async function syncToNativeApp() {
  try {
    const r = await chrome.storage.sync.get([
      STORAGE_KEYS.TRACKED_DOMAINS,
      STORAGE_KEYS.SCROLL_DATA,
      STORAGE_KEYS.SCROLL_LIMIT_MS
    ]);
    const trackedDomains = r[STORAGE_KEYS.TRACKED_DOMAINS] || [];
    const scrollData = r[STORAGE_KEYS.SCROLL_DATA] || {};
    const scrollLimitMs = r[STORAGE_KEYS.SCROLL_LIMIT_MS] ?? 30 * 60 * 1000;

    const browser = typeof chrome !== 'undefined' ? chrome : typeof browser !== 'undefined' ? browser : null;
    if (browser?.runtime?.sendNativeMessage) {
      await browser.runtime.sendNativeMessage(NATIVE_APP, {
        type: 'syncFromExtension',
        trackedDomains,
        scrollData,
        scrollLimitMs
      });
    }
  } catch (e) {
    // Native app may not be available (e.g. Chrome)
  }
}

// Get config from native app (domains, limit) and merge into extension storage
async function pullConfigFromNativeApp() {
  try {
    const browser = typeof chrome !== 'undefined' ? chrome : typeof browser !== 'undefined' ? browser : null;
    if (!browser?.runtime?.sendNativeMessage) return;

    const response = await browser.runtime.sendNativeMessage(NATIVE_APP, { type: 'getConfig' });
    if (response?.ok && response.trackedDomains) {
      await chrome.storage.sync.set({
        [STORAGE_KEYS.TRACKED_DOMAINS]: response.trackedDomains
      });
    }
    if (response?.ok && response.scrollLimitMs != null) {
      await chrome.storage.sync.set({
        [STORAGE_KEYS.SCROLL_LIMIT_MS]: response.scrollLimitMs
      });
    }
  } catch (e) {
    // Native app may not be available
  }
}

// Start sync loop and pull config on startup
chrome.runtime.onStartup?.addListener(() => {
  pullConfigFromNativeApp();
  setInterval(syncToNativeApp, SYNC_INTERVAL_MS);
});

chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'sync') syncToNativeApp();
});

// Initial sync and config pull
pullConfigFromNativeApp();
setInterval(syncToNativeApp, SYNC_INTERVAL_MS);
