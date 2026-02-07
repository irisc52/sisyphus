/**
 * Sisyphus - Popup Script
 * Domain tracking/selection UI and persistent storage via chrome.storage.sync
 */
document.addEventListener('DOMContentLoaded', async () => {
  // --- ELEMENTS ---
  const domainInput = document.getElementById('domain-input');
  const addDomainBtn = document.getElementById('add-domain-btn');
  const addCurrentBtn = document.getElementById('add-current-btn');
  const currentDomainSection = document.getElementById('current-domain-section');
  const currentDomainName = document.getElementById('current-domain-name');
  const domainList = document.getElementById('domain-list');
  const statsList = document.getElementById('stats-list');
  const emptyState = document.getElementById('empty-state');
  
  // NEW: Mode Selector Element
  const modeSelect = document.getElementById('mode-select'); 

  // =========================================================
  // 1. NEW: MODE SELECTOR LOGIC
  // =========================================================
  if (modeSelect) {
    // Load saved mode
    chrome.storage.sync.get(['settings'], (result) => {
      const settings = result.settings || {};
      if (settings.mode) {
        modeSelect.value = settings.mode;
      }
    });

    // Handle changes
    modeSelect.addEventListener('change', (e) => {
      const newMode = e.target.value;
      chrome.storage.sync.get(['settings'], (result) => {
        const settings = result.settings || {};
        settings.mode = newMode;
        
        chrome.storage.sync.set({ settings }, () => {
          // Send message to background to update immediately
          chrome.runtime.sendMessage({ type: 'SET_MODE', mode: newMode });
          
          // Reload the active tab so you see the effect instantly
          chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
            if (tabs[0] && tabs[0].id) {
              chrome.tabs.reload(tabs[0].id);
            }
          });
        });
      });
    });
  }

  // =========================================================
  // 2. EXISTING DOMAIN MANAGEMENT LOGIC
  // =========================================================

  // Helper: Get clean domain from URL
  const getDomain = (url) => {
    try {
      const urlObj = new URL(url);
      return urlObj.hostname.replace(/^www\./, '');
    } catch {
      return null;
    }
  };

  // Helper: Render the UI lists
  const renderUI = async () => {
    const data = await chrome.storage.sync.get(['trackedDomains', 'scrollData']);
    const domains = data.trackedDomains || [];
    const scrollData = data.scrollData || {};

    // A. Render "Tracked Domains" List
    domainList.innerHTML = '';
    if (domains.length === 0) {
      emptyState.classList.remove('hidden');
    } else {
      emptyState.classList.add('hidden');
      domains.forEach(domain => {
        const li = document.createElement('li');
        li.innerHTML = `
          <span class="domain-name">${domain}</span>
          <button data-domain="${domain}">Remove</button>
        `;
        // Remove button click handler
        li.querySelector('button').addEventListener('click', async (e) => {
          const targetDomain = e.target.dataset.domain;
          const verified = confirm(`Stop tracking ${targetDomain}?`);
          if (verified) {
            const newData = await chrome.storage.sync.get(['trackedDomains']);
            const newDomains = (newData.trackedDomains || []).filter(d => d !== targetDomain);
            await chrome.storage.sync.set({ trackedDomains: newDomains });
            renderUI(); // Re-render
            
            // Reload if we are on that page to clear effects
            const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
            if (tab && getDomain(tab.url) === targetDomain) {
              chrome.tabs.reload(tab.id);
            }
          }
        });
        domainList.appendChild(li);
      });
    }

    // B. Render "Today's Stats" List
    statsList.innerHTML = '';
    
    // Sort domains by time spent (highest first)
    const sortedDomains = domains.sort((a, b) => {
      const timeA = scrollData[a]?.totalMs || 0;
      const timeB = scrollData[b]?.totalMs || 0;
      return timeB - timeA;
    });

    sortedDomains.forEach(domain => {
      const ms = scrollData[domain]?.totalMs || 0;
      if (ms > 0) {
        const minutes = Math.floor(ms / 60000);
        const seconds = Math.floor((ms % 60000) / 1000);
        
        const div = document.createElement('div');
        div.className = 'stats-row';
        div.innerHTML = `
          <span class="domain">${domain}</span>
          <span class="time">${minutes}m ${seconds}s</span>
        `;
        statsList.appendChild(div);
      }
    });
  };

  // Helper: Add a new domain
  const addDomain = async (domain) => {
    if (!domain) return;
    
    const data = await chrome.storage.sync.get(['trackedDomains']);
    const domains = data.trackedDomains || [];
    
    if (!domains.includes(domain)) {
      domains.push(domain);
      await chrome.storage.sync.set({ trackedDomains: domains });
      domainInput.value = '';
      renderUI();
      return true;
    }
    return false;
  };

  // --- EVENT LISTENERS ---

  addDomainBtn.addEventListener('click', () => {
    addDomain(domainInput.value.trim());
  });

  addCurrentBtn.addEventListener('click', async () => {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tab) {
      const domain = getDomain(tab.url);
      if (domain) addDomain(domain);
    }
  });

  // =========================================================
  // 3. INITIALIZATION & BUG FIX
  // =========================================================
  
  renderUI();

  // Check current tab status
  const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
  
  if (activeTab && activeTab.url) {
    const currentDomain = getDomain(activeTab.url);
    
    // UI Update: Show current domain name
    if (currentDomain) {
      currentDomainName.textContent = currentDomain;
      
      const data = await chrome.storage.sync.get(['trackedDomains']);
      const domains = data.trackedDomains || [];
      
      if (domains.includes(currentDomain)) {
        addCurrentBtn.textContent = 'Already Tracked';
        addCurrentBtn.disabled = true;
        addCurrentBtn.style.opacity = '0.5';
      }

      // FIX: Explicitly ask background for this specific URL's stats
      // This prevents the background from seeing "chrome-extension://" and resetting the level
      chrome.runtime.sendMessage({ 
        type: 'GET_INTERVENTION_LEVEL', 
        url: activeTab.url 
      }, (response) => {
        // Optional: You can display the current level in the UI here if you want
        console.log("Current Level for this tab:", response.level);
      });

    } else {
      currentDomainSection.style.display = 'none';
    }
  }
});