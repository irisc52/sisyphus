/**
 * Sisyphus - Anti-Doomscrolling Extension
 * Background service worker - handles storage, 24-hour reset logic, and intervention levels
 */

const STORAGE_KEYS = {
  TRACKED_DOMAINS: 'trackedDomains',
  SCROLL_DATA: 'scrollData',
  SETTINGS: 'settings'
};

const HOURS_24_MS = 24 * 60 * 60 * 1000;

const InterventionLevel = {
  OBSERVE: 0,      // Just tracking, no effects
  GENTLE: 1,       // Grayscale + life clock  
  MODERATE: 2,     // + Blur + vignette + quotes
  AGGRESSIVE: 3,   // + Click delay + dopamine counter + opportunity cost
  NUCLEAR: 4       // + Break overlay (last resort)
};

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
 * Calculate intervention level based on usage patterns and time since install
 * Implements "boiling frog" gradual escalation
 */
async function getInterventionLevel(domain) {
  const result = await chrome.storage.sync.get([
    STORAGE_KEYS.SCROLL_DATA,
    STORAGE_KEYS.SETTINGS,
    'installDate'
  ]);
  
  const scrollData = result[STORAGE_KEYS.SCROLL_DATA] || {};
  const settings = result[STORAGE_KEYS.SETTINGS] || {};
  const installDate = result.installDate || Date.now();
  
  const daysSinceInstall = (Date.now() - installDate) / (24 * 60 * 60 * 1000);
  const scrollTime = scrollData[domain]?.totalMs || 0;
  const minutes = scrollTime / 60000;
  
  // Check if user has disabled interventions for this domain
  if (settings.disabledDomains && settings.disabledDomains.includes(domain)) {
    return InterventionLevel.OBSERVE;
  }
  
  // Week 1: Just observe - let them see the tracking works
  if (daysSinceInstall < 7) {
    return InterventionLevel.OBSERVE;
  }
  
  // Week 2: Gentle nudges after 20 minutes
  if (daysSinceInstall < 14) {
    return minutes > 20 ? InterventionLevel.GENTLE : InterventionLevel.OBSERVE;
  }
  
  // Week 3: Start escalating
  if (daysSinceInstall < 21) {
    if (minutes < 15) return InterventionLevel.OBSERVE;
    if (minutes < 30) return InterventionLevel.GENTLE;
    return InterventionLevel.MODERATE;
  }
  
  // Week 4+: Full graduated intervention
  if (minutes < 10) return InterventionLevel.OBSERVE;
  if (minutes < 20) return InterventionLevel.GENTLE;
  if (minutes < 35) return InterventionLevel.MODERATE;
  if (minutes < 50) return InterventionLevel.AGGRESSIVE;
  return InterventionLevel.NUCLEAR; // Go nuclear after 50min
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

  // NEW: Get intervention level for current domain
  if (message.type === 'GET_INTERVENTION_LEVEL') {
    const domain = getDomainKey(sender.url || message.url);
    if (domain) {
      getInterventionLevel(domain).then(level => {
        getScrollDataWithReset().then(scrollData => {
          const minutes = (scrollData[domain]?.totalMs || 0) / 60000;
          sendResponse({ level, minutes });
        });
      });
      return true;
    }
  }

  // NEW: Log override events (when user bypasses nuclear intervention)
  if (message.type === 'LOG_OVERRIDE') {
    const domain = message.domain;
    console.log(`[Sisyphus] User overrode intervention on ${domain}`);
    
    // Could track overrides to increase friction in future
    chrome.storage.local.get(['overrides'], (result) => {
      const overrides = result.overrides || {};
      overrides[domain] = (overrides[domain] || 0) + 1;
      chrome.storage.local.set({ overrides });
    });
    
    sendResponse({ success: true });
    return true;
  }
});

/**
 * Initialize install date on first install
 * This is critical for the boiling frog escalation
 */
chrome.runtime.onInstalled.addListener((details) => {
  if (details.reason === 'install') {
    chrome.storage.sync.set({ 
      installDate: Date.now() 
    });
    console.log('[Sisyphus] Extension installed - tracking start date');
  }
  
  // Also ensure install date exists on update
  chrome.storage.sync.get(['installDate'], (result) => {
    if (!result.installDate) {
      chrome.storage.sync.set({ installDate: Date.now() });
    }
  });
});

/**
 * Log when browser starts up (for debugging)
 */
chrome.runtime.onStartup.addListener(() => {
  console.log('[Sisyphus] Browser started, service worker active');
});

// Export for popup (via chrome.runtime.getBackgroundPage or messaging)
// Popup will use chrome.storage directly and messaging for background logic
