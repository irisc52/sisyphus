/**
 * Sisyphus - Intervention Effects Library
 * All visual and interaction disruption effects for graduated intervention
 */

const SisyphusEffects = {
  
  // =========================================================
  // VISUAL EFFECTS
  // =========================================================
  
  applyGrayscale(intensity = 1.0) {
    const pct = Math.round(Math.max(0, Math.min(1, intensity)) * 100);
    document.documentElement.style.filter = `grayscale(${pct}%)`;
  },
  
  removeGrayscale() {
    document.documentElement.style.filter = '';
  },
  
  applyBlur(intensity = 3) {
    const existing = document.documentElement.style.filter || '';
    const grayscaleMatch = existing.match(/grayscale\([^)]+\)/);
    const grayscale = grayscaleMatch ? grayscaleMatch[0] : '';
    document.documentElement.style.filter = `${grayscale} blur(${intensity}px)`.trim();
  },
  
  applyVignette() {
    if (document.getElementById('sisyphus-vignette')) return;
    
    const vignette = document.createElement('div');
    vignette.id = 'sisyphus-vignette';
    vignette.style.cssText = `
      position: fixed;
      inset: 0;
      pointer-events: none;
      background: radial-gradient(
        circle at center,
        transparent 30%,
        rgba(0,0,0,0.7) 100%
      );
      z-index: 999998;
      transition: opacity 0.5s;
    `;
    document.body.appendChild(vignette);
  },
  
  removeVignette() {
    const vignette = document.getElementById('sisyphus-vignette');
    if (vignette) {
      vignette.style.opacity = '0';
      setTimeout(() => vignette.remove(), 500);
    }
  },
  
  reduceContrast() {
    document.documentElement.style.filter = 'grayscale(100%) contrast(60%) brightness(0.8)';
  },
  
  shrinkViewport(scale = 0.85) {
    document.documentElement.style.transform = `scale(${scale})`;
    document.documentElement.style.transformOrigin = 'top center';
  },
  
  resetViewport() {
    document.documentElement.style.transform = '';
  },
  
  // =========================================================
  // PSYCHOLOGICAL NUDGES
  // =========================================================
  
  showLifeClock(minutes) {
    let lifeClock = document.getElementById('sisyphus-life-clock');
    
    if (!lifeClock) {
      lifeClock = document.createElement('div');
      lifeClock.id = 'sisyphus-life-clock';
      lifeClock.style.cssText = `
        position: fixed;
        top: 10px;
        right: 10px;
        background: rgba(0,0,0,0.9);
        color: #ff4444;
        padding: 12px 16px;
        border-radius: 8px;
        font-size: 14px;
        z-index: 999999;
        font-family: -apple-system, sans-serif;
        box-shadow: 0 4px 12px rgba(0,0,0,0.5);
        transition: opacity 0.3s;
      `;
      document.body.appendChild(lifeClock);
    }
    
    const hours = (minutes / 60).toFixed(1);
    const percentOfDay = ((minutes / 1440) * 100).toFixed(1);
    
    lifeClock.innerHTML = `
      <strong>⏳ ${hours}h wasted</strong><br>
      <small>${percentOfDay}% of your day</small><br>
      <small style="color: #888;">You'll never get this back</small>
    `;
  },
  
  hideLifeClock() {
    const clock = document.getElementById('sisyphus-life-clock');
    if (clock) {
      clock.style.opacity = '0';
      setTimeout(() => clock.remove(), 300);
    }
  },
  
  showRegretQuote() {
    // Don't spam quotes
    if (document.getElementById('sisyphus-quote')) return;
    
    const quotes = [
      "Is this really what you want to be doing?",
      "Your future self will wish you stopped",
      "Every scroll is a choice",
      "What could you be creating instead?",
      "This content will be forgotten tomorrow",
      "Your attention is worth more than this",
      "How many times will you refresh today?",
      "Nothing new is coming",
      "You're trading time for distraction"
    ];
    
    const quote = document.createElement('div');
    quote.id = 'sisyphus-quote';
    quote.style.cssText = `
      position: fixed;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      font-size: 28px;
      color: rgba(255,255,255,0.9);
      text-align: center;
      pointer-events: none;
      z-index: 999998;
      text-shadow: 0 0 20px black;
      padding: 40px;
      max-width: 600px;
      font-family: -apple-system, sans-serif;
      animation: fadeInOut 4s;
      font-weight: 500;
    `;
    
    const style = document.createElement('style');
    style.textContent = `
      @keyframes fadeInOut {
        0%, 100% { opacity: 0; }
        10%, 90% { opacity: 1; }
      }
    `;
    quote.appendChild(style);
    
    quote.textContent = quotes[Math.floor(Math.random() * quotes.length)];
    document.body.appendChild(quote);
    
    setTimeout(() => quote.remove(), 4000);
  },
  
  showDopamineCounter() {
    let counter = document.getElementById('sisyphus-dopamine-counter');
    
    if (!counter) {
      counter = document.createElement('div');
      counter.id = 'sisyphus-dopamine-counter';
      counter.style.cssText = `
        position: fixed;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        font-size: 120px;
        color: rgba(255,0,0,0.3);
        pointer-events: none;
        z-index: 999997;
        font-weight: bold;
        text-shadow: 0 0 20px rgba(255,0,0,0.5);
        font-family: system-ui;
      `;
      document.body.appendChild(counter);
      
      let scrollCount = 0;
      window._sisyphusScrollCounter = () => {
        scrollCount++;
        counter.textContent = scrollCount;
      };
      window.addEventListener('scroll', window._sisyphusScrollCounter, { passive: true });
    }
  },
  
  hideDopamineCounter() {
    const counter = document.getElementById('sisyphus-dopamine-counter');
    if (counter) counter.remove();
    if (window._sisyphusScrollCounter) {
      window.removeEventListener('scroll', window._sisyphusScrollCounter);
      window._sisyphusScrollCounter = null;
    }
  },
  
  showOpportunityCost(minutes) {
    let cost = document.getElementById('sisyphus-opportunity-cost');
    
    if (!cost) {
      cost = document.createElement('div');
      cost.id = 'sisyphus-opportunity-cost';
      cost.style.cssText = `
        position: fixed;
        bottom: 10px;
        left: 10px;
        background: rgba(0,0,0,0.85);
        color: #ffaa00;
        padding: 12px 16px;
        border-radius: 8px;
        font-size: 13px;
        z-index: 999999;
        font-family: -apple-system, sans-serif;
        max-width: 280px;
        line-height: 1.5;
      `;
      document.body.appendChild(cost);
    }
    
    const alternatives = [
      "You could have read 10 pages",
      "You could have learned 20 new words",
      "You could have done 100 pushups",
      "You could have meditated",
      "You could have called a friend",
      "You could have written a page",
      "You could have practiced an instrument",
      "You could have cooked a meal"
    ];
    
    const alt = alternatives[Math.floor(Math.random() * alternatives.length)];
    cost.innerHTML = `<strong>Instead of this...</strong><br>${alt}`;
  },
  
  hideOpportunityCost() {
    const cost = document.getElementById('sisyphus-opportunity-cost');
    if (cost) cost.remove();
  },
  
  // =========================================================
  // INTERACTION DISRUPTION
  // =========================================================
  
  addClickDelay(delayMs = 1000) {
    if (window._sisyphusClickDelay) return;
    
    const handler = (e) => {
      // Don't block extension UI elements
      if (e.target.closest('#sisyphus-life-clock, #sisyphus-quote, #sisyphus-opportunity-cost')) {
        return;
      }
      
      e.preventDefault();
      e.stopPropagation();
      
      const target = e.target;
      const rect = target.getBoundingClientRect();
      
      // Show click delay indicator
      const indicator = document.createElement('div');
      indicator.style.cssText = `
        position: fixed;
        left: ${rect.left + rect.width/2}px;
        top: ${rect.top + rect.height/2}px;
        width: 40px;
        height: 40px;
        margin: -20px 0 0 -20px;
        border: 3px solid #ff4444;
        border-radius: 50%;
        pointer-events: none;
        z-index: 99999999;
        animation: clickDelayPulse ${delayMs}ms ease-out;
      `;
      
      const style = document.createElement('style');
      style.textContent = `
        @keyframes clickDelayPulse {
          0% { transform: scale(0.5); opacity: 1; }
          100% { transform: scale(2); opacity: 0; }
        }
      `;
      indicator.appendChild(style);
      document.body.appendChild(indicator);
      
      setTimeout(() => {
        indicator.remove();
        target.click();
      }, delayMs);
    };
    
    document.addEventListener('click', handler, true);
    window._sisyphusClickDelay = handler;
  },
  
  removeClickDelay() {
    if (window._sisyphusClickDelay) {
      document.removeEventListener('click', window._sisyphusClickDelay, true);
      window._sisyphusClickDelay = null;
    }
  },
  
  // =========================================================
  // AGGRESSIVE INTERVENTIONS
  // =========================================================
  
  showFakeLoader() {
    // Don't spam loaders
    if (document.getElementById('sisyphus-loader')) return;
    
    const loader = document.createElement('div');
    loader.id = 'sisyphus-loader';
    loader.style.cssText = `
      position: fixed;
      inset: 0;
      background: rgba(0,0,0,0.7);
      display: flex;
      align-items: center;
      justify-content: center;
      z-index: 999999;
      backdrop-filter: blur(5px);
    `;
    loader.innerHTML = `
      <div style="
        border: 4px solid #333;
        border-top: 4px solid white;
        border-radius: 50%;
        width: 50px;
        height: 50px;
        animation: spin 1s linear infinite;
      "></div>
      <style>
        @keyframes spin {
          to { transform: rotate(360deg); }
        }
      </style>
    `;
    document.body.appendChild(loader);
    setTimeout(() => loader.remove(), 3000);
  },
  
  flipUpsideDown() {
    document.documentElement.style.transform = 'rotate(180deg)';
  },
  
  flipRightSideUp() {
    document.documentElement.style.transform = '';
  },
  
  showBreakOverlay(minutes) {
    if (document.getElementById('sisyphus-break-overlay')) return;
    
    const overlay = document.createElement('div');
    overlay.id = 'sisyphus-break-overlay';
    overlay.style.cssText = `
      position: fixed;
      inset: 0;
      background: rgba(26, 26, 46, 0.98);
      display: flex;
      align-items: center;
      justify-content: center;
      z-index: 9999999;
      backdrop-filter: blur(10px);
    `;
    
    overlay.innerHTML = `
      <div style="
        text-align: center;
        color: #eaeaea;
        max-width: 500px;
        padding: 40px;
      ">
        <div style="font-size: 64px; margin-bottom: 20px;">🪨</div>
        <h1 style="margin: 0 0 16px; font-size: 28px; font-family: -apple-system, sans-serif;">
          You've been here for ${Math.floor(minutes)} minutes
        </h1>
        <p style="color: #aaa; margin-bottom: 32px; font-family: -apple-system, sans-serif;">
          Your brain craves novelty, but endless scrolling isn't helping.
        </p>
        
        <div style="display: flex; gap: 12px; justify-content: center; flex-wrap: wrap;">
          <button id="sisyphus-take-break" style="
            padding: 12px 24px;
            background: #e94560;
            color: white;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-size: 16px;
            font-weight: 500;
            font-family: -apple-system, sans-serif;
          ">Close this tab</button>
          
          <button id="sisyphus-override" style="
            padding: 12px 24px;
            background: transparent;
            color: #888;
            border: 1px solid #444;
            border-radius: 8px;
            cursor: pointer;
            font-size: 16px;
            font-family: -apple-system, sans-serif;
            opacity: 0.5;
          " disabled>Continue anyway (<span id="sisyphus-countdown">10</span>s)</button>
        </div>
        
        <p style="
          margin-top: 24px;
          font-size: 12px;
          color: #666;
          font-family: -apple-system, sans-serif;
        ">You can adjust settings in the extension popup</p>
      </div>
    `;
    
    document.body.appendChild(overlay);
    
    // Countdown logic
    let countdownSeconds = 10;
    const overrideBtn = overlay.querySelector('#sisyphus-override');
    const countdownSpan = overlay.querySelector('#sisyphus-countdown');
    
    const countdown = setInterval(() => {
      countdownSeconds--;
      countdownSpan.textContent = countdownSeconds;
      
      if (countdownSeconds <= 0) {
        clearInterval(countdown);
        overrideBtn.textContent = 'Continue anyway';
        overrideBtn.disabled = false;
        overrideBtn.style.opacity = '1';
      }
    }, 1000);
    
    overlay.querySelector('#sisyphus-take-break').addEventListener('click', () => {
      window.close();
    });
    
    overrideBtn.addEventListener('click', () => {
      if (countdownSeconds <= 0) {
        overlay.remove();
        // Log override event
        chrome.runtime.sendMessage({ 
          type: 'LOG_OVERRIDE', 
          domain: window.location.hostname 
        });
      }
    });
  },
  
  hideBreakOverlay() {
    const overlay = document.getElementById('sisyphus-break-overlay');
    if (overlay) overlay.remove();
  },
  
  // =========================================================
  // CLEANUP
  // =========================================================
  
  removeAllEffects() {
    this.removeGrayscale();
    this.removeVignette();
    this.removeClickDelay();
    this.hideLifeClock();
    this.hideDopamineCounter();
    this.hideOpportunityCost();
    this.flipRightSideUp();
    this.resetViewport();
    this.hideBreakOverlay();
    document.documentElement.style.filter = '';
    document.documentElement.style.transform = '';
  }
};

// Make available globally for content script
window.SisyphusEffects = SisyphusEffects;
