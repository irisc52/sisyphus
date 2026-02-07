import { useState, useEffect } from 'react'
import { SunIcon } from 'lucide-react'
import { storage } from '../shared/storage'
import './dashboard.css'

function Dashboard() {
  const [data, setData] = useState({
    domains: [],
    timeLimit: 15,
    scrollTime: 0,
    streaks: 0
  })

  const loadData = () => {
    storage.getAll().then(result => {
      setData({
        domains: result.domains || [],
        timeLimit: result.timeLimit || 15,
        scrollTime: result.scrollTime || 0,
        streaks: result.streaks || 0
      })
    })
  }

  useEffect(() => {
    loadData()

    // Listen for real-time updates (works in extension and app polyfill)
    storage.onChange((changes) => {
      setData(prev => ({
        ...prev,
        ...(changes.domains && { domains: changes.domains.newValue ?? prev.domains }),
        ...(changes.timeLimit && { timeLimit: changes.timeLimit.newValue ?? prev.timeLimit }),
        ...(changes.scrollTime && { scrollTime: changes.scrollTime.newValue ?? prev.scrollTime }),
        ...(changes.streaks && { streaks: changes.streaks.newValue ?? prev.streaks })
      }))
    })

    // Poll for updates every 5s (helps when running in app WebView)
    const interval = setInterval(loadData, 5000)
    return () => clearInterval(interval)
  }, [])

  const formatTime = (seconds) => {
    const hours = Math.floor(seconds / 3600)
    const mins = Math.floor((seconds % 3600) / 60)
    if (hours > 0) {
      return `${hours}h ${mins}m`
    }
    return `${mins}m`
  }

  return (
    <div className="dashboard">
      <header>
        <h1>⛰️ Sisyphus</h1>
        <p className="subtitle">Track your progress fighting doomscrolling</p>
      </header>

      <div className="stats-grid">
        <div className="stat-card">
          <h3>Time Scrolled Today</h3>
          <div className="stat-value">{formatTime(data.scrollTime)}</div>
          <div className="stat-label">out of {data.timeLimit} min limit</div>
        </div>

        <div className="stat-card">
          <h3>Current Streak</h3>
          <div className="stat-value">{data.streaks}</div>
          <div className="stat-label">days under limit</div>
        </div>

        <div className="stat-card">
          <h3>Blocked Domains</h3>
          <div className="stat-value">{data.domains.length}</div>
          <div className="stat-label">sites being tracked</div>
        </div>

        <div className="stat-card">
          <h3>Time Saved</h3>
          <div className="stat-value">~2.5h</div>
          <div className="stat-label">this week (estimated)</div>
        </div>
      </div>

      <div className="content-grid">
        <div className="card domains-list">
          <h2> Tracked Domains </h2>
          {data.domains.length === 0 ? (
            <p className="empty-state">No domains added yet. Add some in the popup!</p>
          ) : (
            <ul>
              {data.domains.map(domain => (
                <li key={domain}>
                  <span className="domain-icon">🌐</span>
                  <span className="domain-name">{domain}</span>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="card progress-section">
          <h2>📊 Weekly Progress</h2>
          <div className="progress-placeholder">
            <div className="chart-bars">
              <div className="bar" style={{height: '60%'}}><span>M</span></div>
              <div className="bar" style={{height: '40%'}}><span>T</span></div>
              <div className="bar" style={{height: '80%'}}><span>W</span></div>
              <div className="bar" style={{height: '30%'}}><span>T</span></div>
              <div className="bar" style={{height: '50%'}}><span>F</span></div>
              <div className="bar" style={{height: '20%'}}><span>S</span></div>
              <div className="bar" style={{height: '10%'}}><span>S</span></div>
            </div>
            <p className="chart-label">Minutes scrolled per day</p>
          </div>
        </div>
      </div>

      <div className="card tips-section">
        <h2>💡 Tips</h2>
        <ul className="tips-list">
          <li>The resistance increases gradually - you'll notice it after {data.timeLimit} minutes</li>
          <li>Leaving and coming back won't reset the timer (it persists for 24 hours)</li>
          <li>Try setting a lower time limit as you build better habits</li>
          <li>Track multiple platforms to see your total time across all sites</li>
        </ul>
      </div>
    </div>
  )
}

export default Dashboard