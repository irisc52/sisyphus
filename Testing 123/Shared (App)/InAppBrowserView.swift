//
//  InAppBrowserView.swift
//  Sisyphus
//
//  In-app browser: user picks a tracked domain, opens it here with grayscale + touch friction.
//  Merged with friend's WebView (viewport, mobile prefs, touch-based friction, native-first feel).
//

import SwiftUI
import WebKit

struct InAppBrowserView: View {
    let url: URL
    let domain: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var data = SisyphusData.shared

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                InAppWebViewRepresentable(
                    url: url,
                    domain: domain,
                    scrollLimitMs: data.scrollLimitMs,
                    grayscaleSeconds: data.getGrayscaleSeconds(host: domain),
                    onScrollTime: { data.applyScrollTimeUpdate(domain: $0, additionalMs: $1) },
                    onGrayscaleTick: { data.setGrayscaleSeconds(host: $0, $1) },
                    onRequestClose: { dismiss() }
                )
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(domain)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("Today: \(data.formatDuration(ms: data.domainsWithStats.first { $0.domain == domain }?.timeMs ?? 0))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            EmptyView()
        }
    }
}

private struct InAppWebViewRepresentable: UIViewControllerRepresentable {
    let url: URL
    let domain: String
    let scrollLimitMs: Int64
    let grayscaleSeconds: Int
    let onScrollTime: (String, Int64) -> Void
    let onGrayscaleTick: (String, Int) -> Void
    let onRequestClose: () -> Void

    func makeUIViewController(context: Context) -> InAppWebViewController {
        InAppWebViewController(
            url: url,
            domain: domain,
            scrollLimitMs: scrollLimitMs,
            grayscaleSeconds: grayscaleSeconds,
            onScrollTime: onScrollTime,
            onGrayscaleTick: onGrayscaleTick,
            onRequestClose: onRequestClose
        )
    }

    func updateUIViewController(_ uiViewController: InAppWebViewController, context: Context) {}
}

private class InAppWebViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {
    let url: URL
    let domain: String
    let scrollLimitMs: Int64
    let grayscaleSeconds: Int
    let onScrollTime: (String, Int64) -> Void
    let onGrayscaleTick: (String, Int) -> Void
    let onRequestClose: () -> Void
    private var webView: WKWebView?
    /// Native timer: report time every 5s while browser is open (script-based reporting is unreliable on many sites).
    private var sessionTimeTimer: Timer?
    private let sessionReportInterval: TimeInterval = 5.0

    init(url: URL, domain: String, scrollLimitMs: Int64, grayscaleSeconds: Int,
         onScrollTime: @escaping (String, Int64) -> Void, onGrayscaleTick: @escaping (String, Int) -> Void,
         onRequestClose: @escaping () -> Void) {
        self.url = url
        self.domain = domain
        self.scrollLimitMs = scrollLimitMs
        self.grayscaleSeconds = grayscaleSeconds
        self.onScrollTime = onScrollTime
        self.onGrayscaleTick = onGrayscaleTick
        self.onRequestClose = onRequestClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()

        let contentController = WKUserContentController()
        contentController.add(self, name: "sisyphus")

        // Config for Sisyphus (persisted grayscale, reporting)
        let configJSON: [String: Any] = [
            "tracked": true,
            "scrollLimitMs": NSNumber(value: scrollLimitMs),
            "grayscaleSeconds": NSNumber(value: grayscaleSeconds),
            "host": domain
        ]
        let configData = try? JSONSerialization.data(withJSONObject: configJSON)
        let configStr = configData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        contentController.addUserScript(WKUserScript(
            source: "window.__SISYPHUS_CONFIG__ = \(configStr);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        // Friend's viewport script (mobile-friendly)
        let viewportScript = WKUserScript(
            source: """
            (() => {
              try {
                let meta = document.querySelector('meta[name="viewport"]');
                if (!meta) {
                  meta = document.createElement('meta');
                  meta.name = 'viewport';
                  document.head.appendChild(meta);
                }
                meta.content = 'width=device-width, initial-scale=1.0, viewport-fit=cover';
              } catch (e) {}
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(viewportScript)

        // Inject at document start so we run before redirects/SPA replace the document; also inject at end as fallback.
        contentController.addUserScript(WKUserScript(
            source: Self.injectedScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        contentController.addUserScript(WKUserScript(
            source: Self.injectedScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let wv = WKWebView(frame: view.bounds, configuration: config)
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        wv.navigationDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.bounces = true
        wv.scrollView.alwaysBounceVertical = true
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"

        view.addSubview(wv)
        webView = wv
        var req = URLRequest(url: url)
        req.cachePolicy = .useProtocolCachePolicy
        wv.load(req)
    }

    /// Numbers from JS postMessage often arrive as NSNumber; cast to Int64/Int safely.
    private static func int64(from value: Any?) -> Int64? {
        guard let v = value else { return nil }
        if let n = v as? Int { return Int64(n) }
        if let n = v as? Int64 { return n }
        if let n = v as? Double { return Int64(n) }
        if let n = v as? NSNumber { return n.int64Value }
        return nil
    }
    private static func int(from value: Any?) -> Int? {
        guard let v = value else { return nil }
        if let n = v as? Int { return n }
        if let n = v as? Double { return Int(n) }
        if let n = v as? NSNumber { return n.intValue }
        return nil
    }

    /// Get string from message body (JS can send NSString).
    private static func string(from value: Any?) -> String? {
        guard let v = value else { return nil }
        if let s = v as? String { return s }
        if let s = v as? NSString { return s as String }
        return nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "sisyphus" else { return }
        // Body can be NSDictionary or [String: Any] depending on WebKit; support both.
        let bodyDict: NSDictionary? = (message.body as? NSDictionary)
            ?? (message.body as? [String: Any]).map { $0 as NSDictionary }
        guard let body = bodyDict else { return }
        let type = Self.string(from: body["type"]) ?? (body["type"] as? String) ?? ""
        let hostFromMessage = (Self.string(from: body["host"]) ?? body["host"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? domain
        let normalizedHost = hostFromMessage.replacingOccurrences(of: "www.", with: "", options: .anchored)
        switch type {
        case "UPDATE_SCROLL_TIME":
            guard let ms = Self.int64(from: body["ms"]), ms >= 0 else { return }
            DispatchQueue.main.async { [onScrollTime] in
                onScrollTime(normalizedHost.isEmpty ? self.domain : normalizedHost, ms)
            }
        case "GRAYSCALE_TICK":
            if let total = Self.int(from: body["totalSeconds"]) {
                DispatchQueue.main.async { [onGrayscaleTick] in
                    onGrayscaleTick(normalizedHost.isEmpty ? self.domain : normalizedHost, total)
                }
            }
        case "REQUEST_CLOSE":
            DispatchQueue.main.async { [onRequestClose] in
                onRequestClose()
            }
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Re-inject config and script so we run in the final document (after redirects/SPA load).
        let configJSON: [String: Any] = [
            "tracked": true,
            "scrollLimitMs": NSNumber(value: scrollLimitMs),
            "grayscaleSeconds": NSNumber(value: grayscaleSeconds),
            "host": domain
        ]
        let configData = try? JSONSerialization.data(withJSONObject: configJSON)
        let configStr = configData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let runScript = "window.__SISYPHUS_SCRIPT_RAN = false; window.__SISYPHUS_CONFIG__ = \(configStr); \(Self.injectedScript)"
        webView.evaluateJavaScript(runScript, completionHandler: nil)

        // Native timer: report session time every 5s so the dashboard updates regardless of page script.
        sessionTimeTimer?.invalidate()
        let domain = self.domain
        let report: (String, Int64) -> Void = onScrollTime
        let reportMs = Int64(sessionReportInterval * 1000)
        sessionTimeTimer = Timer.scheduledTimer(withTimeInterval: sessionReportInterval, repeats: true) { [weak self] _ in
            guard self != nil else { return }
            DispatchQueue.main.async { report(domain, reportMs) }
        }
        RunLoop.main.add(sessionTimeTimer!, forMode: .common)
        // Report once immediately so "Today" updates right away
        DispatchQueue.main.async { report(domain, reportMs) }
    }

    deinit {
        sessionTimeTimer?.invalidate()
        sessionTimeTimer = nil
    }

    // MARK: - Injected JS: grayscale + touch friction + reporting + SisyphusEffects (graduated interventions)
    private static var injectedScript: String {
        """
        (() => {
          if (window.__SISYPHUS_SCRIPT_RAN) return;
          window.__SISYPHUS_SCRIPT_RAN = true;
          const cfg = window.__SISYPHUS_CONFIG__ || {};
          const tracked = !!cfg.tracked;
          const host = cfg.host || (document.location && document.location.hostname) || '';
          let grayscaleSeconds = typeof cfg.grayscaleSeconds === 'number' ? cfg.grayscaleSeconds : 0;

          function getCurrentHost() {
            try {
              var h = (document.location && document.location.hostname) ? document.location.hostname : '';
              return h ? h.replace(/^www\\./, '') : (host || '');
            } catch (e) { return host || ''; }
          }

          function send(msg) {
            try {
              msg.host = getCurrentHost();
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.sisyphus)
                window.webkit.messageHandlers.sisyphus.postMessage(msg);
            } catch (e) {}
          }

          if (!tracked) return;

          const GRAY_START_AFTER_SEC = 10;
          const GRAY_RAMP_SEC = 20;
          const FRICTION_START_AFTER_SCROLL_SEC = 10;
          const FRICTION_RAMP_SEC = 20;
          const MIN_MULT = 0.20;
          const MANUAL_GAIN = 1.35;
          const REPORT_INTERVAL_MS = 5000;
          const TIER_1_SEC = 120;
          const TIER_2_SEC = 300;
          const TIER_3_SEC = 600;
          const TIER_4_SEC = 900;

          const clamp01 = (x) => Math.max(0, Math.min(1, x));
          const now = () => performance.now();
          let firstScrollAt = null;
          let scrollReportLastAt = null;
          let appliedTier1 = false, appliedTier2 = false, appliedTier3 = false, appliedTier4 = false;
          let extraBlurPx = 0;

          function frictionMult() {
            if (firstScrollAt === null) return 1;
            const t = (now() - firstScrollAt) / 1000;
            if (t < FRICTION_START_AFTER_SCROLL_SEC) return 1;
            const r = clamp01((t - FRICTION_START_AFTER_SCROLL_SEC) / FRICTION_RAMP_SEC);
            return 1 - r * r * (1 - MIN_MULT);
          }

          function grayLevel() {
            if (grayscaleSeconds < GRAY_START_AFTER_SEC) return 0;
            return clamp01((grayscaleSeconds - GRAY_START_AFTER_SEC) / GRAY_RAMP_SEC);
          }

          function applyGrayscaleToPage(pct) {
            const el = document.documentElement;
            let f = 'grayscale(' + pct + '%)';
            if (extraBlurPx > 0) f += ' blur(' + extraBlurPx + 'px)';
            el.style.filter = f;
          }

          if (!window.__SISYPHUS_INTERVALS_SET) {
            window.__SISYPHUS_INTERVALS_SET = true;
            setInterval(() => {
              grayscaleSeconds += 1;
              if (document.documentElement) {
                const pct = Math.round(grayLevel() * 100);
                applyGrayscaleToPage(pct);
              }
              send({ type: 'GRAYSCALE_TICK', totalSeconds: grayscaleSeconds });
            }, 1000);
            setInterval(() => {
              const t = Date.now();
              const elapsed = scrollReportLastAt != null ? (t - scrollReportLastAt) : REPORT_INTERVAL_MS;
              scrollReportLastAt = t;
              if (elapsed > 0) send({ type: 'UPDATE_SCROLL_TIME', ms: elapsed });
            }, REPORT_INTERVAL_MS);
            scrollReportLastAt = Date.now();
          }

          function isScrollable(el) {
            if (!el) return false;
            const s = getComputedStyle(el);
            return (s.overflowY === 'auto' || s.overflowY === 'scroll') && el.scrollHeight > el.clientHeight + 1;
          }
          function findScrollContainerFromPoint(x, y) {
            let el = document.elementFromPoint(x, y);
            while (el && el !== document.documentElement) {
              if (isScrollable(el)) return el;
              el = el.parentElement;
            }
            return document.scrollingElement || document.documentElement;
          }
          const THRESH_PX = 8;
          let tracking = false, tookOver = false, startX = 0, startY = 0, lastY = 0, scroller = null;
          function resetGesture() { tracking = false; tookOver = false; scroller = null; }
          document.addEventListener('touchstart', (e) => {
            if (!e.touches || e.touches.length !== 1) { resetGesture(); return; }
            tracking = true; tookOver = false;
            startX = e.touches[0].clientX; startY = e.touches[0].clientY; lastY = startY; scroller = null;
          }, { passive: true, capture: true });
          document.addEventListener('touchmove', (e) => {
            if (!tracking) return;
            if (!e.touches || e.touches.length !== 1) { resetGesture(); return; }
            const x = e.touches[0].clientX, y = e.touches[0].clientY;
            const dyTotal = y - startY, dxTotal = x - startX;
            if (Math.abs(dyTotal) < THRESH_PX) return;
            if (Math.abs(dyTotal) < Math.abs(dxTotal)) return;
            if (firstScrollAt === null) { firstScrollAt = now(); scrollReportLastAt = Date.now(); }
            const m = frictionMult();
            if (m >= 0.999) { lastY = y; tookOver = false; scroller = null; return; }
            if (!tookOver) { tookOver = true; scroller = findScrollContainerFromPoint(x, y); lastY = y; }
            e.preventDefault();
            const dy = y - lastY; lastY = y;
            const delta = -dy * m * MANUAL_GAIN;
            if (!scroller) scroller = findScrollContainerFromPoint(x, y);
            if (scroller) scroller.scrollTop += delta;
          }, { passive: false, capture: true });
          document.addEventListener('touchend', resetGesture, { passive: true, capture: true });
          document.addEventListener('touchcancel', resetGesture, { passive: true, capture: true });

          const SisyphusEffects = {
            applyGrayscale(intensity) {
              const pct = Math.round(clamp01(intensity != null ? intensity : 1) * 100);
              applyGrayscaleToPage(pct);
            },
            removeGrayscale() { document.documentElement.style.filter = ''; },
            applyBlur(intensity) {
              extraBlurPx = intensity != null ? intensity : 3;
              const pct = Math.round(grayLevel() * 100);
              applyGrayscaleToPage(pct);
            },
            applyVignette() {
              if (document.getElementById('sisyphus-vignette')) return;
              const v = document.createElement('div');
              v.id = 'sisyphus-vignette';
              v.style.cssText = 'position:fixed;inset:0;pointer-events:none;background:radial-gradient(circle at center,transparent 30%,rgba(0,0,0,0.7) 100%);z-index:999998;transition:opacity 0.5s;';
              document.body.appendChild(v);
            },
            removeVignette() {
              const v = document.getElementById('sisyphus-vignette');
              if (v) { v.style.opacity = '0'; setTimeout(() => v.remove(), 500); }
            },
            showLifeClock(minutes) {
              let c = document.getElementById('sisyphus-life-clock');
              if (!c) {
                c = document.createElement('div');
                c.id = 'sisyphus-life-clock';
                c.style.cssText = 'position:fixed;top:10px;right:10px;background:rgba(0,0,0,0.9);color:#ff4444;padding:12px 16px;border-radius:8px;font-size:14px;z-index:999999;font-family:-apple-system,sans-serif;';
                document.body.appendChild(c);
              }
              const hours = (minutes / 60).toFixed(1);
              const pct = ((minutes / 1440) * 100).toFixed(1);
              c.innerHTML = '<strong>⏳ ' + hours + 'h wasted</strong><br><small>' + pct + '% of your day</small><br><small style="color:#888">You\'ll never get this back</small>';
            },
            hideLifeClock() {
              const c = document.getElementById('sisyphus-life-clock');
              if (c) { c.style.opacity = '0'; setTimeout(() => c.remove(), 300); }
            },
            showRegretQuote() {
              if (document.getElementById('sisyphus-quote')) return;
              const quotes = ['Is this really what you want to be doing?','Your future self will wish you stopped','Every scroll is a choice','What could you be creating instead?','This content will be forgotten tomorrow','Your attention is worth more than this','How many times will you refresh today?','Nothing new is coming','You\'re trading time for distraction'];
              const q = document.createElement('div');
              q.id = 'sisyphus-quote';
              q.style.cssText = 'position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);font-size:22px;color:rgba(255,255,255,0.9);text-align:center;pointer-events:none;z-index:999998;text-shadow:0 0 20px black;padding:40px;max-width:90%;font-family:-apple-system,sans-serif;';
              q.textContent = quotes[Math.floor(Math.random() * quotes.length)];
              document.body.appendChild(q);
              setTimeout(() => q.remove(), 4000);
            },
            showOpportunityCost() {
              let cost = document.getElementById('sisyphus-opportunity-cost');
              if (!cost) {
                cost = document.createElement('div');
                cost.id = 'sisyphus-opportunity-cost';
                cost.style.cssText = 'position:fixed;bottom:10px;left:10px;background:rgba(0,0,0,0.85);color:#ffaa00;padding:12px 16px;border-radius:8px;font-size:13px;z-index:999999;font-family:-apple-system,sans-serif;max-width:280px;';
                document.body.appendChild(cost);
              }
              const alts = ['You could have read 10 pages','You could have learned 20 new words','You could have done 100 pushups','You could have meditated','You could have called a friend','You could have written a page','You could have practiced an instrument','You could have cooked a meal'];
              cost.innerHTML = '<strong>Instead of this...</strong><br>' + alts[Math.floor(Math.random() * alts.length)];
            },
            hideOpportunityCost() {
              const c = document.getElementById('sisyphus-opportunity-cost');
              if (c) c.remove();
            },
            showBreakOverlay(minutes) {
              if (document.getElementById('sisyphus-break-overlay')) return;
              const overlay = document.createElement('div');
              overlay.id = 'sisyphus-break-overlay';
              overlay.style.cssText = 'position:fixed;inset:0;background:rgba(26,26,46,0.98);display:flex;align-items:center;justify-content:center;z-index:9999999;backdrop-filter:blur(10px);';
              overlay.innerHTML = '<div style="text-align:center;color:#eaeaea;max-width:500px;padding:40px;font-family:-apple-system,sans-serif"><div style="font-size:64px;margin-bottom:20px">🪨</div><h1 style="margin:0 0 16px;font-size:28px">You\'ve been here for ' + Math.floor(minutes) + ' minutes</h1><p style="color:#aaa;margin-bottom:32px">Your brain craves novelty, but endless scrolling isn\'t helping.</p><div style="display:flex;gap:12px;justify-content:center;flex-wrap:wrap"><button id="sisyphus-take-break" style="padding:12px 24px;background:#e94560;color:white;border:none;border-radius:8px;cursor:pointer;font-size:16px;font-weight:500">Close & leave</button><button id="sisyphus-override" style="padding:12px 24px;background:transparent;color:#888;border:1px solid #444;border-radius:8px;cursor:pointer;font-size:16px;opacity:0.5" disabled><span id="sisyphus-countdown">10</span>s to continue</button></div></div>';
              document.body.appendChild(overlay);
              let cd = 10;
              const span = overlay.querySelector('#sisyphus-countdown');
              const btn = overlay.querySelector('#sisyphus-override');
              const ti = setInterval(() => {
                cd--;
                span.textContent = cd;
                if (cd <= 0) { clearInterval(ti); btn.textContent = 'Continue anyway'; btn.disabled = false; btn.style.opacity = '1'; }
              }, 1000);
              overlay.querySelector('#sisyphus-take-break').addEventListener('click', () => { send({ type: 'REQUEST_CLOSE' }); });
              btn.addEventListener('click', () => { if (cd <= 0) { overlay.remove(); send({ type: 'LOG_OVERRIDE', domain: host }); } });
            }
          };
          window.SisyphusEffects = SisyphusEffects;

          setInterval(() => {
            if (!document.body) return;
            const min = grayscaleSeconds / 60;
            if (grayscaleSeconds >= TIER_4_SEC && !appliedTier4) {
              appliedTier4 = true;
              SisyphusEffects.showBreakOverlay(min);
            } else if (grayscaleSeconds >= TIER_3_SEC && !appliedTier3) {
              appliedTier3 = true;
              SisyphusEffects.applyVignette();
              SisyphusEffects.applyBlur(2);
            } else if (grayscaleSeconds >= TIER_2_SEC && !appliedTier2) {
              appliedTier2 = true;
              SisyphusEffects.showLifeClock(min);
              SisyphusEffects.showRegretQuote();
            } else if (grayscaleSeconds >= TIER_1_SEC && !appliedTier1) {
              appliedTier1 = true;
              SisyphusEffects.showOpportunityCost();
            }
          }, 10000);

          if (grayscaleSeconds > 0) {
            const pct = Math.round(grayLevel() * 100);
            applyGrayscaleToPage(pct);
          }
        })();
        """
    }
}
