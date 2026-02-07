/**
 * Sisyphus - Popup Script
 * Domain tracking/selection UI and persistent storage via chrome.storage.sync
 */

const STORAGE_KEYS = {
  TRACKED_DOMAINS: 'trackedDomains',
  SCROLL_DATA: 'scrollData',
  SCROLL_LIMIT_MS: 'scrollLimitMs'
};

// Open dashboard when button clicked
document.getElementById('open-dashboard-btn')?.addEventListener('click', () => {
  chrome.tabs.create({
    url: chrome.runtime.getURL('popup-ui/dashboard.html')
  });
});

const DEFAULT_SCROLL_LIMIT_MS = 30 * 60 * 1000; // 30 min

const HOURS_24_MS = 24 * 60 * 60 * 1000;

function normalizeDomain(input) {
  if (!input || typeof input !== 'string') return null;
  let domain = input.trim().toLowerCase();
  domain = domain.replace(/^https?:\/\//, '').replace(/^www\./, '').split('/')[0];
  if (!domain) return null;
  return domain;
}

function formatDuration(ms) {
  if (ms < 60000) return `${Math.floor(ms / 1000)}s`;
  const mins = Math.floor(ms / 60000);
  const secs = Math.floor((ms % 60000) / 1000);
  if (mins < 60) return `${mins}m ${secs}s`;
  const hours = Math.floor(mins / 60);
  const remainMins = mins % 60;
  return `${hours}h ${remainMins}m`;
}

function shouldReset(timestamp) {
  return Date.now() - timestamp >= HOURS_24_MS;
}

async function getScrollDataWithReset() {
  const result = await chrome.storage.sync.get([STORAGE_KEYS.SCROLL_DATA]);
  let scrollData = result[STORAGE_KEYS.SCROLL_DATA] || {};
  const trackedDomains = (await chrome.storage.sync.get([STORAGE_KEYS.TRACKED_DOMAINS]))[STORAGE_KEYS.TRACKED_DOMAINS] || [];

  let changed = false;
  for (const domain of Object.keys(scrollData)) {
    const entry = scrollData[domain];
    if (entry && shouldReset(entry.lastResetTimestamp)) {
      scrollData[domain] = { totalMs: 0, lastResetTimestamp: Date.now() };
      changed = true;
    }
  }
  if (changed) {
    await chrome.storage.sync.set({ [STORAGE_KEYS.SCROLL_DATA]: scrollData });
  }
  return scrollData;
}

async function getTrackedDomains() {
  const result = await chrome.storage.sync.get([STORAGE_KEYS.TRACKED_DOMAINS]);
  return result[STORAGE_KEYS.TRACKED_DOMAINS] || [];
}

async function addDomain(domain) {
  const normalized = normalizeDomain(domain);
  if (!normalized) return false;
  const domains = await getTrackedDomains();
  if (domains.includes(normalized)) return false;
  domains.push(normalized);
  await chrome.storage.sync.set({ [STORAGE_KEYS.TRACKED_DOMAINS]: domains });
  return true;
}

async function removeDomain(domain) {
  const normalized = normalizeDomain(domain);
  if (!normalized) return;
  const domains = await getTrackedDomains();
  const filtered = domains.filter((d) => d !== normalized);
  await chrome.storage.sync.set({ [STORAGE_KEYS.TRACKED_DOMAINS]: filtered });
}

async function getScrollLimitMs() {
  const result = await chrome.storage.sync.get([STORAGE_KEYS.SCROLL_LIMIT_MS]);
  const ms = result[STORAGE_KEYS.SCROLL_LIMIT_MS];
  if (ms == null || ms < 0) return DEFAULT_SCROLL_LIMIT_MS;
  return ms;
}

async function setScrollLimitMs(ms) {
  await chrome.storage.sync.set({ [STORAGE_KEYS.SCROLL_LIMIT_MS]: ms });
}

function renderDomainList(domains) {
  const list = document.getElementById('domain-list');
  const empty = document.getElementById('empty-state');
  list.innerHTML = '';
  if (domains.length === 0) {
    empty.classList.remove('hidden');
    return;
  }
  empty.classList.add('hidden');
  domains.forEach((domain) => {
    const li = document.createElement('li');
    li.innerHTML = `
      <span class="domain-name">${escapeHtml(domain)}</span>
      <button type="button" data-domain="${escapeHtml(domain)}">Remove</button>
    `;
    li.querySelector('button').addEventListener('click', async () => {
      await removeDomain(domain);
      await refreshUI();
    });
    list.appendChild(li);
  });
}

function renderStats(scrollData, trackedDomains) {
  const container = document.getElementById('stats-list');
  container.innerHTML = '';
  const domainsWithData = trackedDomains.filter((d) => scrollData[d] && scrollData[d].totalMs > 0);
  if (domainsWithData.length === 0) return;
  domainsWithData.forEach((domain) => {
    const entry = scrollData[domain];
    const row = document.createElement('div');
    row.className = 'stats-row';
    row.innerHTML = `
      <span class="domain">${escapeHtml(domain)}</span>
      <span class="time">${formatDuration(entry.totalMs)}</span>
    `;
    container.appendChild(row);
  });
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

async function refreshUI() {
  const [domains, scrollData] = await Promise.all([
    getTrackedDomains(),
    getScrollDataWithReset()
  ]);
  renderDomainList(domains);
  renderStats(scrollData, domains);
}

async function init() {
  const domainInput = document.getElementById('domain-input');
  const addBtn = document.getElementById('add-domain-btn');
  const addCurrentBtn = document.getElementById('add-current-btn');
  const currentDomainSection = document.getElementById('current-domain-section');
  const currentDomainName = document.getElementById('current-domain-name');
  const scrollLimitSelect = document.getElementById('scroll-limit');
  const scrollLimitCustom = document.getElementById('scroll-limit-custom');

  // Scroll limit UI
  const limitMs = await getScrollLimitMs();
  const limitMins = limitMs === 0 ? 0 : Math.round(limitMs / 60000);
  const presetMatch = scrollLimitSelect.querySelector(`option[value="${limitMins}"]`);
  if (presetMatch) {
    scrollLimitSelect.value = String(limitMins);
    scrollLimitCustom.classList.add('hidden');
  } else if (limitMs === 0) {
    scrollLimitSelect.value = '0';
    scrollLimitCustom.classList.add('hidden');
  } else {
    scrollLimitSelect.value = 'custom';
    scrollLimitCustom.classList.remove('hidden');
    scrollLimitCustom.value = limitMins;
  }

  scrollLimitSelect.addEventListener('change', async () => {
    const val = scrollLimitSelect.value;
    if (val === 'custom') {
      scrollLimitCustom.classList.remove('hidden');
      scrollLimitCustom.focus();
      const mins = parseInt(scrollLimitCustom.value, 10) || 30;
      await setScrollLimitMs(mins * 60 * 1000);
    } else {
      scrollLimitCustom.classList.add('hidden');
      const mins = parseInt(val, 10) || 0;
      await setScrollLimitMs(mins * 60 * 1000);
    }
  });

  scrollLimitCustom.addEventListener('change', async () => {
    const mins = Math.max(0, Math.min(480, parseInt(scrollLimitCustom.value, 10) || 0));
    await setScrollLimitMs(mins * 60 * 1000);
    scrollLimitCustom.value = mins;
  });

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab?.url && (tab.url.startsWith('http://') || tab.url.startsWith('https://'))) {
    const domain = normalizeDomain(new URL(tab.url).hostname);
    currentDomainName.textContent = domain || '—';
    addCurrentBtn.onclick = async () => {
      if (domain && (await addDomain(domain))) {
        domainInput.value = '';
        await refreshUI();
      }
    };
  } else {
    currentDomainSection.style.display = 'none';
  }

  addBtn.onclick = async () => {
    const value = domainInput.value;
    if (await addDomain(value)) {
      domainInput.value = '';
      await refreshUI();
    }
  };

  domainInput.addEventListener('keydown', async (e) => {
    if (e.key === 'Enter') {
      const value = domainInput.value;
      if (await addDomain(value)) {
        domainInput.value = '';
        await refreshUI();
      }
    }
  });

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === 'sync') refreshUI();
  });

  await refreshUI();
}

init();
