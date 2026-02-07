/**
 * Sisyphus - Content Script (MERGED)
 *
 * Keeps your partner’s popup-controlled domain tracking + background reporting,
 * and preserves your grayscale + scroll-friction behavior.
 *
 * Behavior:
 * - Only activates grayscale + friction if the current URL/domain is "tracked"
 *   according to the popup/background logic (IS_DOMAIN_TRACKED).
 * - While tracked:
 *    - Reports time deltas to background every REPORT_INTERVAL_MS (partner behavior)
 *    - Applies grayscale ramp based on locally-tracked active seconds on this domain
 *      stored in chrome.storage.local (your behavior)
 *    - Applies scroll friction ramp after FRICTION_START_AFTER_SCROLL seconds of scrolling (your behavior)
 * - When untracked or tab hidden: stops reporting + disables grayscale + friction.
 */

(function () {
  'use strict';

  // =========================================================
  // Partner config: reporting / tracking toggles
  // =========================================================
  const REPORT_INTERVAL_MS = 5000; // Report "time spent" every 5 seconds
  const CHECK_TRACKING_INTERVAL_MS = 2000;

  let isTracked = false;
  let scrollStartTime = null;
  let reportIntervalId = null;

  // =========================================================
  // Your config: grayscale + friction
  // =========================================================

  // --- Grayscale ---
  const GRAY_START_AFTER = 10; // seconds on site before grayscale begins
  const GRAY_RAMP_SEC = 20; // seconds to reach full grayscale

  // --- Scroll friction ---
  const FRICTION_START_AFTER_SCROLL = 10; // seconds after user starts scrolling
  const FRICTION_RAMP_SEC = 20; // seconds to get to max friction
  const MIN_SCROLL_MULT = 0.05; // at max friction, only 0.5% of scroll remains (very noticeable)

  // Storage key per host
  const host = location.hostname.replace(/^www\./, '').replace(/^m\./, '');
  const KEY = `time_${host}`;

  // Active time tracking (for grayscale)
  let active = document.visibilityState === 'visible' && document.hasFocus();
  let lastTick = Date.now();
  let grayscaleIntervalId = null;

  // Scroll friction state
  let firstScrollAtMs = null;
  let pending = new Map(); // Map<element, {dx, dy}>
  let rafScheduled = false;

  // Debug meter (optional)
  let meterIntervalId = null;

  console.log('[Sisyphus] content loaded on', location.hostname);

  // =========================================================
  // Helpers
  // =========================================================
  function clamp01(x) {
    return Math.max(0, Math.min(1, x));
  }

  function setGrayscale(level01) {
    const pct = Math.round(clamp01(level01) * 100);
    document.documentElement.style.filter = `grayscale(${pct}%)`;
  }

  function clearGrayscale() {
    document.documentElement.style.filter = '';
  }

  function grayFromSeconds(sec) {
    if (sec < GRAY_START_AFTER) return 0;
    return clamp01((sec - GRAY_START_AFTER) / GRAY_RAMP_SEC);
  }

  function isScrollable(el) {
    if (!el || el === document.documentElement) return false;
    const style = getComputedStyle(el);
    const overflowY = style.overflowY;
    const overflowX = style.overflowX;

    const canScrollY =
      (overflowY === 'auto' || overflowY === 'scroll') &&
      el.scrollHeight > el.clientHeight + 1;
    const canScrollX =
      (overflowX === 'auto' || overflowX === 'scroll') &&
      el.scrollWidth > el.clientWidth + 1;
    return canScrollY || canScrollX;
  }

  function findScrollContainer(startEl) {
    let el = startEl;
    while (el && el !== document.body && el !== document.documentElement) {
      if (isScrollable(el)) return el;
      el = el.parentElement;
    }
    return document.scrollingElement || document.documentElement;
  }

  function scrollMultiplier(nowMs) {
    if (firstScrollAtMs === null) return 1;

    const sinceFirstScrollSec = (nowMs - firstScrollAtMs) / 1000;
    if (sinceFirstScrollSec < FRICTION_START_AFTER_SCROLL) return 1;

    const t =
      (sinceFirstScrollSec - FRICTION_START_AFTER_SCROLL) / FRICTION_RAMP_SEC;
    const ramp = clamp01(t);

    // Aggressive curve (quadratic)
    const eased = ramp * ramp;
    return 1 - eased * (1 - MIN_SCROLL_MULT);
  }

  function scheduleApply() {
    if (rafScheduled) return;
    rafScheduled = true;

    requestAnimationFrame(() => {
      rafScheduled = false;

      for (const [el, vec] of pending.entries()) {
        if (
          el === document.scrollingElement ||
          el === document.documentElement ||
          el === document.body
        ) {
          window.scrollBy(vec.dx, vec.dy);
        } else {
          el.scrollBy({ left: vec.dx, top: vec.dy, behavior: 'auto' });
        }
      }
      pending.clear();
    });
  }

  function addPending(el, dx, dy) {
    const cur = pending.get(el) || { dx: 0, dy: 0 };
    cur.dx += dx;
    cur.dy += dy;
    pending.set(el, cur);
    scheduleApply();
  }

  function ensureMeter() {
    let m = document.getElementById('__sf_meter');
    if (m) return m;
    m = document.createElement('div');
    m.id = '__sf_meter';
    Object.assign(m.style, {
      position: 'fixed',
      right: '12px',
      bottom: '12px',
      zIndex: '2147483647',
      padding: '8px 10px',
      borderRadius: '10px',
      background: 'rgba(0,0,0,0.65)',
      color: 'white',
      font: '12px system-ui',
      pointerEvents: 'none'
    });
    m.textContent = 'friction: 1.00';
    document.documentElement.appendChild(m);
    return m;
  }

  function removeMeter() {
    const m = document.getElementById('__sf_meter');
    if (m) m.remove();
  }

  // =========================================================
  // Partner logic: check tracked domains via background
  // =========================================================
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

  function startReportingToBackground() {
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
      scrollStartTime = Date.now();
    }, REPORT_INTERVAL_MS);
  }

  function stopReportingToBackground() {
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

  // =========================================================
  // Your logic: grayscale timer (active seconds) + friction
  // =========================================================
  function tickTimeForGrayscale() {
    const now = Date.now();
    const elapsedSec = Math.floor((now - lastTick) / 1000);
    lastTick = now;

    if (!active || elapsedSec <= 0) return;

    chrome.storage.local.get([KEY], (res) => {
      const prev = typeof res[KEY] === 'number' ? res[KEY] : 0;
      const total = prev + elapsedSec;

      chrome.storage.local.set({ [KEY]: total });
      setGrayscale(grayFromSeconds(total));
    });
  }

  function startGrayscale() {
    if (grayscaleIntervalId) return;

    // Initialize grayscale from stored time
    chrome.storage.local.get([KEY], (res) => {
      const sec = typeof res[KEY] === 'number' ? res[KEY] : 0;
      setGrayscale(grayFromSeconds(sec));
    });

    lastTick = Date.now();
    grayscaleIntervalId = setInterval(tickTimeForGrayscale, 1000);
  }

  function stopGrayscale() {
    if (grayscaleIntervalId) {
      clearInterval(grayscaleIntervalId);
      grayscaleIntervalId = null;
    }
    clearGrayscale();
  }

  function resetFrictionSession() {
    firstScrollAtMs = null;
    pending.clear();
    rafScheduled = false;
  }

  function onWheel(e) {
    // Only apply when tracked + active (and we can still allow wheel events to function normally if not tracked)
    if (!isTracked || !active) return;

    // Don’t mess with pinch-to-zoom on trackpads
    if (e.ctrlKey) return;

    // Initialize scroll session timer
    if (firstScrollAtMs === null) firstScrollAtMs = Date.now();

    const mult = scrollMultiplier(Date.now());

    // Dramatic effect: prevent native scroll and re-apply scaled scroll
    e.preventDefault();

    const target = e.target instanceof Element ? e.target : document.documentElement;
    const scroller = findScrollContainer(target);

    addPending(scroller, e.deltaX * mult, e.deltaY * mult);
  }

  function startFriction() {
    // nothing to "start" other than resetting session; listener is always registered
    resetFrictionSession();

    // Optional debug meter: kept enabled because your original code had it enabled
    if (!meterIntervalId) {
      meterIntervalId = setInterval(() => {
        if (!isTracked || !active) return;
        const m = ensureMeter();
        const mult = scrollMultiplier(Date.now());
        m.textContent = `friction multiplier: ${mult.toFixed(3)}`;
      }, 200);
    }
  }

  function stopFriction() {
    resetFrictionSession();
    if (meterIntervalId) {
      clearInterval(meterIntervalId);
      meterIntervalId = null;
    }
    removeMeter();
  }

  // Always register wheel listener, but it only acts when isTracked && active
  window.addEventListener('wheel', onWheel, { passive: false, capture: true });

  // =========================================================
  // Unified enable/disable based on tracking status
  // =========================================================
  function enableEffectsAndReporting() {
    startReportingToBackground();
    startGrayscale();
    startFriction();
  }

  function disableEffectsAndReporting() {
    stopReportingToBackground();
    stopGrayscale();
    stopFriction();
  }

  async function syncTrackingState() {
    const tracked = await checkIfTracked();
    if (tracked !== isTracked) {
      isTracked = tracked;
      console.log('[Sisyphus] tracked=', isTracked, 'host=', host);

      if (isTracked && !document.hidden) {
        enableEffectsAndReporting();
      } else {
        disableEffectsAndReporting();
      }
    }
  }

  // =========================================================
  // Init + periodic checks
  // =========================================================
  (async function init() {
    await syncTrackingState();

    // Periodically re-check in case user added/removed domain from popup
    setInterval(syncTrackingState, CHECK_TRACKING_INTERVAL_MS);

    // Track active focus (for grayscale)
    document.addEventListener('visibilitychange', () => {
      active = document.visibilityState === 'visible' && document.hasFocus();

      if (document.hidden) {
        // Always stop when hidden (prevents phantom time + avoids messing with page)
        disableEffectsAndReporting();
      } else {
        // Re-enable only if still tracked
        if (isTracked) enableEffectsAndReporting();
      }
    });

    window.addEventListener('focus', () => {
      active = true;
      if (isTracked && !document.hidden) enableEffectsAndReporting();
    });

    window.addEventListener('blur', () => {
      active = false;
      disableEffectsAndReporting();
    });

    // Stop tracking before unload
    window.addEventListener('beforeunload', () => {
      if (isTracked) disableEffectsAndReporting();
    });
  })();
})();
