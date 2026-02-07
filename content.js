/**
 * Sisyphus - Content Script (INTEGRATED WITH INTERVENTIONS)
 *
 * Combines domain tracking, grayscale, friction, AND graduated intervention effects
 */

(function () {
  'use strict';

  // =========================================================
  // Config
  // =========================================================
  const REPORT_INTERVAL_MS = 5000;
  const CHECK_TRACKING_INTERVAL_MS = 2000;
  const INTERVENTION_CHECK_INTERVAL_MS = 30000; // Check interventions every 30s

  // Grayscale config
  const GRAY_START_AFTER = 10;
  const GRAY_RAMP_SEC = 20;

  // Friction config
  const FRICTION_START_AFTER_SCROLL = 10;
  const FRICTION_RAMP_SEC = 20;
  const MIN_SCROLL_MULT = 0.05;

  // =========================================================
  // State
  // =========================================================
  let isTracked = false;
  let scrollStartTime = null;
  let reportIntervalId = null;
  let interventionCheckId = null;
  let currentInterventionLevel = 0;
  let lastInterventionTime = 0;

  // Grayscale state
  const host = location.hostname.replace(/^www\./, '').replace(/^m\./, '');
  const KEY = `time_${host}`;
  let active = document.visibilityState === 'visible' && document.hasFocus();
  let lastTick = Date.now();
  let grayscaleIntervalId = null;

  // Friction state
  let firstScrollAtMs = null;
  let pending = new Map();
  let rafScheduled = false;
  let meterIntervalId = null;

  console.log('[Sisyphus] content loaded on', location.hostname);

  // =========================================================
  // Utility functions
  // =========================================================
  function clamp01(x) {
    return Math.max(0, Math.min(1, x));
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

    const t = (sinceFirstScrollSec - FRICTION_START_AFTER_SCROLL) / FRICTION_RAMP_SEC;
    const ramp = clamp01(t);
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

  // =========================================================
  // Domain tracking (partner logic)
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
  // Grayscale tracking
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
      
      // Only apply base grayscale if no interventions are active
      if (currentInterventionLevel === 0 && window.SisyphusEffects) {
        window.SisyphusEffects.applyGrayscale(grayFromSeconds(total));
      }
    });
  }

  function startGrayscale() {
    if (grayscaleIntervalId) return;

    chrome.storage.local.get([KEY], (res) => {
      const sec = typeof res[KEY] === 'number' ? res[KEY] : 0;
      if (currentInterventionLevel === 0 && window.SisyphusEffects) {
        window.SisyphusEffects.applyGrayscale(grayFromSeconds(sec));
      }
    });

    lastTick = Date.now();
    grayscaleIntervalId = setInterval(tickTimeForGrayscale, 1000);
  }

  function stopGrayscale() {
    if (grayscaleIntervalId) {
      clearInterval(grayscaleIntervalId);
      grayscaleIntervalId = null;
    }
  }

  // =========================================================
  // Friction tracking
  // =========================================================
  function resetFrictionSession() {
    firstScrollAtMs = null;
    pending.clear();
    rafScheduled = false;
  }

  function onWheel(e) {
    if (!isTracked || !active) return;
    if (e.ctrlKey) return;

    if (firstScrollAtMs === null) firstScrollAtMs = Date.now();

    const mult = scrollMultiplier(Date.now());
    e.preventDefault();

    const target = e.target instanceof Element ? e.target : document.documentElement;
    const scroller = findScrollContainer(target);

    addPending(scroller, e.deltaX * mult, e.deltaY * mult);
  }

  function startFriction() {
    resetFrictionSession();
  }

  function stopFriction() {
    resetFrictionSession();
    if (meterIntervalId) {
      clearInterval(meterIntervalId);
      meterIntervalId = null;
    }
  }

  // Register wheel listener
  window.addEventListener('wheel', onWheel, { passive: false, capture: true });

  // =========================================================
  // INTERVENTION SYSTEM (NEW)
  // =========================================================
  async function checkAndApplyInterventions() {
    if (!isTracked) return;
    
    const now = Date.now();
    // Don't check interventions too frequently
    if (now - lastInterventionTime < 10000) return; // 10s cooldown
    
    chrome.runtime.sendMessage(
      { type: 'GET_INTERVENTION_LEVEL', url: window.location.href },
      (response) => {
        if (chrome.runtime.lastError || !response) return;
        
        const { level, minutes } = response;
        applyInterventionLevel(level, minutes);
        lastInterventionTime = now;
      }
    );
  }

  function applyInterventionLevel(level, minutes) {
    if (!window.SisyphusEffects) {
      console.warn('[Sisyphus] SisyphusEffects not loaded yet');
      return;
    }
    
    const effects = window.SisyphusEffects;
    
    // Remove old effects if downgrading
    if (level < currentInterventionLevel) {
      effects.removeAllEffects();
    }
    
    currentInterventionLevel = level;
    
    switch(level) {
      case 0: // OBSERVE - base grayscale + friction only
        effects.removeAllEffects();
        break;
        
      case 1: // GENTLE - grayscale + life clock
        effects.applyGrayscale(1.0);
        effects.showLifeClock(minutes);
        break;
        
      case 2: // MODERATE - + blur + vignette + occasional quotes
        effects.applyGrayscale(1.0);
        effects.applyBlur(2);
        effects.applyVignette();
        effects.showLifeClock(minutes);
        
        // Show regret quote occasionally (10% chance every check)
        if (Math.random() < 0.1) {
          effects.showRegretQuote();
        }
        break;
        
      case 3: // AGGRESSIVE - + click delay + dopamine counter + opportunity cost
        effects.reduceContrast();
        effects.applyBlur(4);
        effects.applyVignette();
        effects.addClickDelay(1500);
        effects.showLifeClock(minutes);
        effects.showDopamineCounter();
        effects.showOpportunityCost(minutes);
        
        // Fake loaders occasionally (15% chance)
        if (Math.random() < 0.15) {
          effects.showFakeLoader();
        }
        
        // Show regret quotes more often (30% chance)
        if (Math.random() < 0.3) {
          effects.showRegretQuote();
        }
        break;
        
      case 4: // NUCLEAR - break overlay
        effects.showBreakOverlay(minutes);
        break;
    }
  }

  // =========================================================
  // Unified enable/disable
  // =========================================================
  function enableEffectsAndReporting() {
    startReportingToBackground();
    startGrayscale();
    startFriction();
    
    // Start intervention checks
    if (!interventionCheckId) {
      interventionCheckId = setInterval(checkAndApplyInterventions, INTERVENTION_CHECK_INTERVAL_MS);
      checkAndApplyInterventions(); // Check immediately
    }
  }

  function disableEffectsAndReporting() {
    stopReportingToBackground();
    stopGrayscale();
    stopFriction();
    
    if (interventionCheckId) {
      clearInterval(interventionCheckId);
      interventionCheckId = null;
    }
    
    // Clean up all effects
    if (window.SisyphusEffects) {
      window.SisyphusEffects.removeAllEffects();
    }
    
    currentInterventionLevel = 0;
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
  // Init + event handlers
  // =========================================================
  (async function init() {
    await syncTrackingState();

    // Periodically re-check tracking status
    setInterval(syncTrackingState, CHECK_TRACKING_INTERVAL_MS);

    // Track active focus
    document.addEventListener('visibilitychange', () => {
      active = document.visibilityState === 'visible' && document.hasFocus();

      if (document.hidden) {
        disableEffectsAndReporting();
      } else {
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

    window.addEventListener('beforeunload', () => {
      if (isTracked) disableEffectsAndReporting();
    });
  })();
})();
