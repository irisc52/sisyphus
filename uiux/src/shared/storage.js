// Centralized Chrome storage functions
// Both popup and dashboard use these

export const storage = {
    // Get all data
    getAll: () => {
        return new Promise((resolve) => {
        if (typeof chrome !== 'undefined' && chrome.storage) {
            chrome.storage.sync.get(
            ['domains', 'timeLimit', 'scrollTime', 'streaks', 'lastActive'],
            (result) => resolve(result)
        )
        } else {
          // Fallback for localhost testing
          resolve({
            domains: ['instagram.com', 'twitter.com'],
            timeLimit: 15,
            scrollTime: 0,
            streaks: 0,
            lastActive: Date.now()
          })
        }
      })
    },
  
    // Save domains
    saveDomains: (domains) => {
      return new Promise((resolve) => {
        if (typeof chrome !== 'undefined' && chrome.storage) {
          chrome.storage.sync.set({ domains }, () => resolve())
        } else {
          resolve()
        }
      })
    },
  
    // Save time limit
    saveTimeLimit: (timeLimit) => {
      return new Promise((resolve) => {
        if (typeof chrome !== 'undefined' && chrome.storage) {
          chrome.storage.sync.set({ timeLimit: parseInt(timeLimit) }, () => resolve())
        } else {
          resolve()
        }
      })
    },
  
    // Update scroll time
    updateScrollTime: (seconds) => {
      return new Promise((resolve) => {
        if (typeof chrome !== 'undefined' && chrome.storage) {
          chrome.storage.sync.get(['scrollTime'], (result) => {
            const newTime = (result.scrollTime || 0) + seconds
            chrome.storage.sync.set({ scrollTime: newTime }, () => resolve(newTime))
          })
        } else {
          resolve(0)
        }
      })
    },
  
    // Listen for changes (so both pages update in real-time)
    onChange: (callback) => {
      if (typeof chrome !== 'undefined' && chrome.storage) {
        chrome.storage.onChanged.addListener((changes, namespace) => {
          callback(changes, namespace)
        })
      }
    }
  }