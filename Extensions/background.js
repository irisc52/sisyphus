/**
 * Sisyphus - Anti-Doomscrolling Extension
 * Background service worker - handles storage, 24-hour reset logic, and domain matching
 */

const STORAGE_KEYS = {
  TRACKED_DOMAINS: 'trackedDomains',
  SCROLL_DATA: 'scrollData',
  SETTINGS: 'settings'
};

const HOURS_24_MS = 24 * 60 * 60 * 1000;

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

// Export for popup (via chrome.runtime.getBackgroundPage or messaging)
// Popup will use chrome.storage directly and messaging for background logic
