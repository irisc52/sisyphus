/**
 * Sisyphus - Content Script (MERGED)
 * Patched:
 * - Popup focus/blur no longer clears grayscale or resets friction session
 * - Scrollbars hidden while tracked to prevent bypass
 * - Friction continues even when page blurs due to extension popup
 * - FIX: ensures wheel listener is registered
 */

(function () {
  'use strict';

  // =========================================================
  // Partner config: reporting / tracking toggles
  // =========================================================
  const REPORT_INTERVAL_MS = 5000;
  const CHECK_TRACKING_INTERVAL_MS = 2000;

  let isTracked = false;
  let scrollStartTime = null;
  let reportIntervalId = null;

  // =========================================================
  // Your config: grayscale + friction
  // =========================================================
  const GRAY_START_AFTER = 10;
  const GRAY_RAMP_SEC = 20;

  const FRICTION_START_AFTER_SCROLL = 10;
  const FRICTION_RAMP_SEC = 20;
  const MIN_SCROLL_MULT = 0.01;

  // Scrollbar hiding toggle
  const HIDE_SCROLLBARS_WHEN_TRACKED = true;
  const SCROLLBAR_STYLE_ID = '__sf_hide_scrollbars';

  const host = location.hostname.replace(/^www\./, '').replace(/^m\./, '');
  const KEY = `time_${host}`;

  // Time tracking only (not used to gate friction)
  let timeActive = document.visibilityState === 'visible' && document.hasFocus();
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

    // quadratic ramp
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
  // Scrollbar hide/show (tracked only)
  // =========================================================
  function installScrollbarHiding() {
    if (!HIDE_SCROLLBARS_WHEN_TRACKED) return;
    if (document.getElementById(SCROLLBAR_STYLE_ID)) return;

    const style = document.createElement('style');
    style.id = SCROLLBAR_STYLE_ID;
    style.textContent = `
      /* Firefox */
      html, body, * { scrollbar-width: none !important; }
      /* WebKit */
      *::-webkit-scrollbar { width: 0 !important; height: 0 !important; }
      *::-webkit-scrollbar-thumb { background: transparent !important; }
      *::-webkit-scrollbar-track { background: transparent !important; }
    `;
    document.documentElement.appendChild(style);
  }

  function removeScrollbarHiding() {
    const style = document.getElementById(SCROLLBAR_STYLE_ID);
    if (style) style.remove();
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
  // Grayscale (time-based)
  // =========================================================
  function tickTimeForGrayscale() {
    const now = Date.now();
    const elapsedSec = Math.floor((now - lastTick) / 1000);
    lastTick = now;

    if (!timeActive || elapsedSec <= 0) return;

    chrome.storage.local.get([KEY], (res) => {
      const prev = typeof res[KEY] === 'number' ? res[KEY] : 0;
      const total = prev + elapsedSec;
      chrome.storage.local.set({ [KEY]: total });
      setGrayscale(grayFromSeconds(total));
    });
  }

  function startGrayscale() {
    if (grayscaleIntervalId) return;

    chrome.storage.local.get([KEY], (res) => {
      const sec = typeof res[KEY] === 'number' ? res[KEY] : 0;
      setGrayscale(grayFromSeconds(sec));
    });

    lastTick = Date.now();
    grayscaleIntervalId = setInterval(tickTimeForGrayscale, 1000);
  }

  function stopGrayscaleFull() {
    if (grayscaleIntervalId) {
      clearInterval(grayscaleIntervalId);
      grayscaleIntervalId = null;
    }
    clearGrayscale();
  }

  function pauseGrayscaleKeepVisual() {
    if (grayscaleIntervalId) {
      clearInterval(grayscaleIntervalId);
      grayscaleIntervalId = null;
    }
    // keep current filter applied
  }

  // =========================================================
  // Friction
  // =========================================================
  function resetFrictionSession() {
    firstScrollAtMs = null;
    pending.clear();
    rafScheduled = false;
  }

  function onWheel(e) {
    // Friction should apply even if the page is blurred by the extension popup.
    if (!isTracked || document.hidden) return;

    // Don’t mess with pinch-to-zoom
    if (e.ctrlKey) return;

    if (firstScrollAtMs === null) firstScrollAtMs = Date.now();

    const mult = scrollMultiplier(Date.now());

    // Apply dramatic friction: cancel native scroll and re-apply scaled scroll
    e.preventDefault();

    const target = e.target instanceof Element ? e.target : document.documentElement;
    const scroller = findScrollContainer(target);

    addPending(scroller, e.deltaX * mult, e.deltaY * mult);
  }

  // FIX: ensure wheel listener is actually registered
  window.addEventListener('wheel', onWheel, { passive: false, capture: true });

  function startFriction() {
    // Do NOT reset friction session here (prevents popup click from resetting)
    if (!meterIntervalId) {
      meterIntervalId = setInterval(() => {
        if (!isTracked || document.hidden) return;
        const m = ensureMeter();
        const mult = scrollMultiplier(Date.now());
        m.textContent = `friction multiplier: ${mult.toFixed(3)}`;
      }, 200);
    }
  }

  function stopFrictionFull() {
    resetFrictionSession();
    if (meterIntervalId) {
      clearInterval(meterIntervalId);
      meterIntervalId = null;
    }
    removeMeter();
  }

  // =========================================================
  // Unified enable/disable
  // =========================================================
  function enableEffectsAndReporting() {
    installScrollbarHiding();
    startReportingToBackground();
    startGrayscale();
    startFriction();
  }

  function disableEffectsAndReportingFull() {
    stopReportingToBackground();
    stopGrayscaleFull();
    stopFrictionFull();
    removeScrollbarHiding();
  }

  async function syncTrackingState() {
    const tracked = await checkIfTracked();
    if (tracked !== isTracked) {
      isTracked = tracked;
      console.log('[Sisyphus] tracked=', isTracked, 'host=', host);

      if (isTracked && !document.hidden) {
        enableEffectsAndReporting();
      } else {
        disableEffectsAndReportingFull();
      }
    }
  }

  // =========================================================
  // Init + periodic checks
  // =========================================================
  (async function init() {
    await syncTrackingState();
    setInterval(syncTrackingState, CHECK_TRACKING_INTERVAL_MS);

    document.addEventListener('visibilitychange', () => {
      timeActive = document.visibilityState === 'visible' && document.hasFocus();

      if (document.hidden) {
        if (isTracked) disableEffectsAndReportingFull();
      } else {
        if (isTracked) enableEffectsAndReporting();
      }
    });

    window.addEventListener('focus', () => {
      timeActive = true;
      if (isTracked && !document.hidden) enableEffectsAndReporting();
    });

    window.addEventListener('blur', () => {
      // Popup opening triggers blur. Pause time/reporting only.
      timeActive = false;

      if (isTracked && !document.hidden) {
        stopReportingToBackground();
        pauseGrayscaleKeepVisual();
        // friction stays ON (wheel handler doesn’t depend on focus)
      } else {
        disableEffectsAndReportingFull();
      }
    });

    window.addEventListener('beforeunload', () => {
      if (isTracked) disableEffectsAndReportingFull();
    });
  })();
})();
