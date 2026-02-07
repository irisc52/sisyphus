import { useState } from 'react'
import reactLogo from './assets/react.svg'
import viteLogo from '/vite.svg'
import './App.css'

function App() {
  const [timeLimit, setTimeLimit] = useState(15) // minutes
  const [domains, setDomains] = useState(['instagram.com', 'twitter.com'])
  const [newDomain, setNewDomain] = useState('')

  const addDomain = () => {
    if (newDomain && !domains.includes(newDomain)) {
      setDomains([...domains, newDomain])
      setNewDomain('')
    }
  }

  const removeDomain = (domain) => {
    setDomains(domains.filter(d => d !== domain))
  }

  return (
    <div className="app">
      <h1>⛰️ Sisyphus</h1>
      <p>Anti-doomscrolling tool</p>

      <div className="section">
        <h2>Time Limit</h2>
        <input 
          type="number" 
          value={timeLimit}
          onChange={(e) => setTimeLimit(e.target.value)}
          min="1"
        />
        <span> minutes before scroll slows down</span>
      </div>

      <div className="section">
        <h2>Blocked Domains</h2>
        <ul>
          {domains.map(domain => (
            <li key={domain}>
              {domain}
              <button onClick={() => removeDomain(domain)}>✕</button>
            </li>
          ))}
        </ul>

        <div>
          <input 
            type="text"
            placeholder="e.g. reddit.com"
            value={newDomain}
            onChange={(e) => setNewDomain(e.target.value)}
          />
          <button onClick={addDomain}>Add Domain</button>
        </div>
      </div>

      <button className="save-btn">Save Settings</button>
    </div>
  )
}

export default App