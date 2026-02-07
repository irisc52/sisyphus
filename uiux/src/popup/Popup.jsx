import { useState, useEffect } from 'react'
import { storage } from '../shared/storage'
import './popup.css'

function Popup() {
  const [domains, setDomains] = useState([])
  const [newDomain, setNewDomain] = useState('')
  const [timeLimit, setTimeLimit] = useState(15)
  const [scrollTime, setScrollTime] = useState(0)

  useEffect(() => {
    // Load initial data
    storage.getAll().then(data => {
      setDomains(data.domains || [])
      setTimeLimit(data.timeLimit || 15)
      setScrollTime(data.scrollTime || 0)
    })

    // Listen for changes from other pages
    storage.onChange((changes) => {
      if (changes.domains) setDomains(changes.domains.newValue)
      if (changes.scrollTime) setScrollTime(changes.scrollTime.newValue)
    })
  }, [])

  const addDomain = () => {
    if (newDomain && !domains.includes(newDomain)) {
      const updated = [...domains, newDomain]
      setDomains(updated)
      storage.saveDomains(updated)
      setNewDomain('')
    }
  }

  const removeDomain = (domain) => {
    const updated = domains.filter(d => d !== domain)
    setDomains(updated)
    storage.saveDomains(updated)
  }

  const openDashboard = () => {
    if (typeof chrome !== 'undefined' && chrome.tabs) {
      chrome.tabs.create({ 
        url: chrome.runtime.getURL('popup-ui/dashboard.html') 
      })
    } else {
      // Fallback for localhost
      window.open('/dashboard.html', '_blank')
    }
  }

  return (
    <div className="popup">
      <div className="header">
        <h2>⛰️ Sisyphus</h2>
        <button onClick={openDashboard} className="dashboard-btn">
          📊 Dashboard
        </button>
      </div>

      <div className="quick-stats">
        <div>Time today: {Math.floor(scrollTime / 60)}m</div>
      </div>

      <div className="section">
        <h3>Blocked Domains</h3>
        <ul>
          {domains.length === 0 ? (
            <li className="empty">No domains added yet</li>
          ) : (
            domains.map(domain => (
              <li key={domain}>
                <span>{domain}</span>
                <button onClick={() => removeDomain(domain)}>✕</button>
              </li>
            ))
          )}
        </ul>
        <div className="add-domain">
          <input 
            type="text"
            placeholder="instagram.com"
            value={newDomain}
            onChange={(e) => setNewDomain(e.target.value)}
            onKeyPress={(e) => e.key === 'Enter' && addDomain()}
          />
          <button onClick={addDomain}>+</button>
        </div>
      </div>

      <div className="section">
        <label>
          Time limit: 
          <input 
            type="number"
            value={timeLimit}
            onChange={(e) => {
              setTimeLimit(e.target.value)
              storage.saveTimeLimit(e.target.value)
            }}
            min="1"
          /> min
        </label>
      </div>
    </div>
  )
}

export default Popup