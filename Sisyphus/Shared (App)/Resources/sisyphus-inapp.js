/**
 * Sisyphus in-app browser script
 * Same grayscale + friction as extension; uses window.__SISYPHUS_CONFIG__ and
 * window.webkit.messageHandlers.sisyphus.postMessage() instead of chrome.*
 */
(function () {
  'use strict';

  const REPORT_INTERVAL_MS = 5000;
  const GRAY_START_AFTER = 10;
  const GRAY_RAMP_SEC = 20;
  const FRICTION_START_AFTER_SCROLL = 10;
  const FRICTION_RAMP_SEC = 20;
  const MIN_SCROLL_MULT = 0.01;
  const SCROLLBAR_STYLE_ID = '__sf_hide_scrollbars';

  const host = location.hostname.replace(/^www\./, '').replace(/^m\./, '');
  let grayscaleSeconds = (window.__SISYPHUS_CONFIG__ && window.__SISYPHUS_CONFIG__.grayscaleSeconds) || 0;
  let isTracked = !!(window.__SISYPHUS_CONFIG__ && window.__SISYPHUS_CONFIG__.tracked);
  let scrollStartTime = null;
  let reportIntervalId = null;
  let timeActive = document.visibilityState === 'visible' && document.hasFocus();
  let lastTick = Date.now();
  let grayscaleIntervalId = null;
  let firstScrollAtMs = null;
  let pending = new Map();
  let rafScheduled = false;

  function send(msg) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.sisyphus) {
        window.webkit.messageHandlers.sisyphus.postMessage(msg);
      }
    } catch (e) {}
  }

  function clamp01(x) {
    return Math.max(0, Math.min(1, x));
  }

  function setGrayscale(level01) {
    const pct = Math.round(clamp01(level01) * 100);
    document.documentElement.style.filter = 'grayscale(' + pct + '%)';
  }

  function grayFromSeconds(sec) {
    if (sec < GRAY_START_AFTER) return 0;
    return clamp01((sec - GRAY_START_AFTER) / GRAY_RAMP_SEC);
  }

  function isScrollable(el) {
    if (!el || el === document.documentElement) return false;
    const style = getComputedStyle(el);
    const oy = style.overflowY, ox = style.overflowX;
    const canY = (oy === 'auto' || oy === 'scroll') && el.scrollHeight > el.clientHeight + 1;
    const canX = (ox === 'auto' || ox === 'scroll') && el.scrollWidth > el.clientWidth + 1;
    return canY || canX;
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
    const sinceSec = (nowMs - firstScrollAtMs) / 1000;
    if (sinceSec < FRICTION_START_AFTER_SCROLL) return 1;
    const t = (sinceSec - FRICTION_START_AFTER_SCROLL) / FRICTION_RAMP_SEC;
    const ramp = clamp01(t);
    const eased = ramp * ramp;
    return 1 - eased * (1 - MIN_SCROLL_MULT);
  }

  function scheduleApply() {
    if (rafScheduled) return;
    rafScheduled = true;
    requestAnimationFrame(function () {
      rafScheduled = false;
      for (var entries = pending.entries(), it = entries.next(); !it.done; it = entries.next()) {
        var pair = it.value, el = pair[0], vec = pair[1];
        if (el === document.scrollingElement || el === document.documentElement || el === document.body) {
          window.scrollBy(vec.dx, vec.dy);
        } else {
          el.scrollBy({ left: vec.dx, top: vec.dy, behavior: 'auto' });
        }
      }
      pending.clear();
    });
  }

  function addPending(el, dx, dy) {
    var cur = pending.get(el) || { dx: 0, dy: 0 };
    cur.dx += dx;
    cur.dy += dy;
    pending.set(el, cur);
    scheduleApply();
  }

  function installScrollbarHiding() {
    if (document.getElementById(SCROLLBAR_STYLE_ID)) return;
    var style = document.createElement('style');
    style.id = SCROLLBAR_STYLE_ID;
    style.textContent = 'html, body, * { scrollbar-width: none !important; } *::-webkit-scrollbar { width: 0 !important; height: 0 !important; }';
    document.documentElement.appendChild(style);
  }

  function removeScrollbarHiding() {
    var style = document.getElementById(SCROLLBAR_STYLE_ID);
    if (style) style.remove();
  }

  function startReporting() {
    if (reportIntervalId) return;
    scrollStartTime = Date.now();
    reportIntervalId = setInterval(function () {
      if (!scrollStartTime) return;
      var elapsed = Date.now() - scrollStartTime;
      send({ type: 'UPDATE_SCROLL_TIME', ms: elapsed, url: window.location.href });
      scrollStartTime = Date.now();
    }, REPORT_INTERVAL_MS);
  }

  function stopReporting() {
    if (reportIntervalId) {
      clearInterval(reportIntervalId);
      reportIntervalId = null;
    }
    if (scrollStartTime) {
      send({ type: 'UPDATE_SCROLL_TIME', ms: Date.now() - scrollStartTime, url: window.location.href });
      scrollStartTime = null;
    }
  }

  function tickGrayscale() {
    var now = Date.now();
    var elapsedSec = Math.floor((now - lastTick) / 1000);
    lastTick = now;
    if (!timeActive || elapsedSec <= 0) return;
    grayscaleSeconds += elapsedSec;
    setGrayscale(grayFromSeconds(grayscaleSeconds));
    send({ type: 'GRAYSCALE_TICK', host: host, totalSeconds: grayscaleSeconds });
  }

  function startGrayscale() {
    if (grayscaleIntervalId) return;
    setGrayscale(grayFromSeconds(grayscaleSeconds));
    lastTick = Date.now();
    grayscaleIntervalId = setInterval(tickGrayscale, 1000);
  }

  function stopGrayscale() {
    if (grayscaleIntervalId) {
      clearInterval(grayscaleIntervalId);
      grayscaleIntervalId = null;
    }
    document.documentElement.style.filter = '';
  }

  function onWheel(e) {
    if (!isTracked || document.hidden) return;
    if (e.ctrlKey) return;
    if (firstScrollAtMs === null) firstScrollAtMs = Date.now();
    var mult = scrollMultiplier(Date.now());
    e.preventDefault();
    var target = e.target instanceof Element ? e.target : document.documentElement;
    var scroller = findScrollContainer(target);
    addPending(scroller, e.deltaX * mult, e.deltaY * mult);
  }

  window.addEventListener('wheel', onWheel, { passive: false, capture: true });

  function enable() {
    installScrollbarHiding();
    startReporting();
    startGrayscale();
  }

  function disable() {
    stopReporting();
    stopGrayscale();
    removeScrollbarHiding();
    firstScrollAtMs = null;
    pending.clear();
  }

  if (isTracked) enable();

  document.addEventListener('visibilitychange', function () {
    timeActive = document.visibilityState === 'visible' && document.hasFocus();
    if (document.hidden && isTracked) disable();
    else if (!document.hidden && isTracked) enable();
  });

  window.addEventListener('beforeunload', function () {
    if (isTracked) disable();
  });
})();
