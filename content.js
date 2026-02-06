/**
 * Sisyphus - Content Script
 * Tracks scroll time on matched domains and reports to background
 */

(function () {
  'use strict';

  const REPORT_INTERVAL_MS = 5000; // Report scroll time every 5 seconds
  const CHECK_TRACKING_INTERVAL_MS = 2000;

  let isTracked = false;
  let scrollStartTime = null;
  let reportIntervalId = null;

  function getCurrentDomain() {
    try {
      const hostname = window.location.hostname;
      return hostname.replace(/^www\./, '');
    } catch {
      return null;
    }
  }

  function checkIfTracked() {
    return new Promise((resolve) => {
      chrome.runtime.sendMessage(
        { type: 'IS_DOMAIN_TRACKED', url: window.location.href },
        (response) => {
          if (chrome.runtime.lastError) {
            resolve(false);
            return;
          }
          resolve(response?.tracked ?? false);
        }
      );
    });
  }

  function startTracking() {
    if (reportIntervalId) return;
    scrollStartTime = Date.now();

    reportIntervalId = setInterval(() => {
      if (!scrollStartTime) return;
      const elapsed = Date.now() - scrollStartTime;
      chrome.runtime.sendMessage({
        type: 'UPDATE_SCROLL_TIME',
        ms: elapsed,
        url: window.location.href
      });
      scrollStartTime = Date.now(); // Reset for next interval
    }, REPORT_INTERVAL_MS);
  }

  function stopTracking() {
    if (reportIntervalId) {
      clearInterval(reportIntervalId);
      reportIntervalId = null;
    }
    if (scrollStartTime) {
      const elapsed = Date.now() - scrollStartTime;
      chrome.runtime.sendMessage({
        type: 'UPDATE_SCROLL_TIME',
        ms: elapsed,
        url: window.location.href
      });
      scrollStartTime = null;
    }
  }

  async function init() {
    const tracked = await checkIfTracked();
    if (tracked !== isTracked) {
      isTracked = tracked;
      if (isTracked) {
        startTracking();
      } else {
        stopTracking();
      }
    }
  }

  // Initial check
  init();

  // Periodically re-check in case user added/removed domain from popup
  setInterval(init, CHECK_TRACKING_INTERVAL_MS);

  // Stop tracking when page is hidden (tab switch, minimize)
  document.addEventListener('visibilitychange', () => {
    if (document.hidden && isTracked) {
      stopTracking();
    } else if (!document.hidden && isTracked) {
      startTracking();
    }
  });

  // Stop tracking before unload
  window.addEventListener('beforeunload', () => {
    if (isTracked) stopTracking();
  });
})();
