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

  function getScrollLimitMs() {
    return new Promise((resolve) => {
      chrome.runtime.sendMessage({ type: 'GET_SCROLL_LIMIT_MS' }, (response) => {
        if (chrome.runtime.lastError) resolve(0); // 0 = unlimited
        else resolve(response?.limitMs ?? 0);
      });
    });
  }

  function getCurrentScrollTime() {
    return new Promise((resolve) => {
      chrome.runtime.sendMessage(
        { type: 'GET_SCROLL_TIME', url: window.location.href },
        (response) => {
          if (chrome.runtime.lastError) resolve(0);
          else resolve(response?.totalMs ?? 0);
        }
      );
    });
  }

  function showHeavyScrollOverlay() {
    if (document.getElementById('sisyphus-heavy-scroll')) return;
    const overlay = document.createElement('div');
    overlay.id = 'sisyphus-heavy-scroll';
    overlay.innerHTML = `
      <div class="sisyphus-overlay-content">
        <h2>🪨 Heavy scroll mode</h2>
        <p>You've hit your daily scroll limit for this site. Take a break?</p>
        <button id="sisyphus-dismiss">Dismiss (scroll anyway)</button>
      </div>
      <style>
        #sisyphus-heavy-scroll {
          position: fixed;
          inset: 0;
          z-index: 2147483647;
          background: rgba(0,0,0,0.7);
          display: flex;
          align-items: center;
          justify-content: center;
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
        }
        #sisyphus-heavy-scroll .sisyphus-overlay-content {
          background: #1a1a2e;
          padding: 24px;
          border-radius: 12px;
          max-width: 320px;
          text-align: center;
          color: #eaeaea;
        }
        #sisyphus-heavy-scroll h2 { margin: 0 0 12px; font-size: 20px; }
        #sisyphus-heavy-scroll p { margin: 0 0 16px; color: #aaa; font-size: 14px; }
        #sisyphus-heavy-scroll button {
          background: #e94560;
          color: white;
          border: none;
          padding: 10px 16px;
          border-radius: 8px;
          cursor: pointer;
          font-size: 14px;
        }
      </style>
    `;
    overlay.querySelector('#sisyphus-dismiss').onclick = () => overlay.remove();
    document.body.appendChild(overlay);
  }

  function isOverLimit(totalMs, limitMs) {
    if (!limitMs || limitMs <= 0) return false;
    return totalMs >= limitMs;
  }

  async function checkHeavyScrollLimit() {
    const [totalMs, limitMs] = await Promise.all([
      getCurrentScrollTime(),
      getScrollLimitMs()
    ]);
    if (isOverLimit(totalMs, limitMs)) {
      showHeavyScrollOverlay();
    }
  }

  function startTracking() {
    if (reportIntervalId) return;
    scrollStartTime = Date.now();

    reportIntervalId = setInterval(async () => {
      if (!scrollStartTime) return;
      const elapsed = Date.now() - scrollStartTime;
      chrome.runtime.sendMessage({
        type: 'UPDATE_SCROLL_TIME',
        ms: elapsed,
        url: window.location.href
      });
      scrollStartTime = Date.now(); // Reset for next interval
      await checkHeavyScrollLimit();
    }, REPORT_INTERVAL_MS);
    // Also check on start (e.g. user refreshed while over limit)
    checkHeavyScrollLimit();
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
