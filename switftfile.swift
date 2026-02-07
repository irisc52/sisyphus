//import SwiftUI
//import WebKit
//import UIKit
//
//struct IGWebView: UIViewRepresentable {
//    typealias UIViewType = WKWebView
//
//    func makeUIView(context: Context) -> WKWebView {
//        let contentController = WKUserContentController()
//        
//        // Inject JS after the page loads
//        let script = WKUserScript(
//            source: injectedScript,
//            injectionTime: .atDocumentEnd,
//            forMainFrameOnly: true
//        )
//        contentController.addUserScript(script)
//
//        let config = WKWebViewConfiguration()
//        config.userContentController = contentController
//
//        let webView = WKWebView(frame: .zero, configuration: config)
//
//        // Make it feel like a browser
//        webView.allowsBackForwardNavigationGestures = true
//        webView.scrollView.bounces = true
//        webView.scrollView.alwaysBounceVertical = true
//        webView.customUserAgent =
//          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
//
//        // Load Instagram web
//        if let url = URL(string: "https://www.instagram.com") {
//            webView.load(URLRequest(url: url))
//        }
//
//        return webView
//    }
//
//    func updateUIView(_ uiView: WKWebView, context: Context) {}
//
//    // MARK: - Injected JavaScript (Grayscale + Scroll Friction)
//    private var injectedScript: String {
//        return """
//        (() => {
//          // ===== CONFIG =====
//          const GRAY_START_AFTER_SEC = 10;  // start grayscale after 10s on page
//          const GRAY_RAMP_SEC = 20;         // ramp to full gray over 20s
//
//          const FRICTION_START_AFTER_SCROLL_SEC = 10; // start friction 10s after first real scroll gesture
//          const FRICTION_RAMP_SEC = 20;
//          const MIN_MULT = 0.20; // aggressive: at max only 20% of motion "sticks"
//
//          const clamp01 = (x) => Math.max(0, Math.min(1, x));
//          const now = () => performance.now();
//
//          // Time on page (for grayscale)
//          const pageStart = now();
//
//          // Time since first scroll gesture (for friction)
//          let firstScrollAt = null;
//
//          function frictionMult() {
//            if (firstScrollAt === null) return 1;
//            const t = (now() - firstScrollAt) / 1000;
//            if (t < FRICTION_START_AFTER_SCROLL_SEC) return 1;
//            const r = clamp01((t - FRICTION_START_AFTER_SCROLL_SEC) / FRICTION_RAMP_SEC);
//            const eased = r * r; // aggressive
//            return 1 - eased * (1 - MIN_MULT);
//          }
//
//          // ---- grayscale ----
//          function grayLevel() {
//            const t = (now() - pageStart) / 1000;
//            if (t < GRAY_START_AFTER_SEC) return 0;
//            return clamp01((t - GRAY_START_AFTER_SEC) / GRAY_RAMP_SEC);
//          }
//
//          setInterval(() => {
//            const pct = Math.round(grayLevel() * 100);
//            document.documentElement.style.filter = `grayscale(${pct}%)`;
//          }, 200);
//
//          // ---- scroll container detection ----
//          function isScrollable(el) {
//            if (!el) return false;
//            const s = getComputedStyle(el);
//            const oy = s.overflowY;
//            return (oy === "auto" || oy === "scroll") && el.scrollHeight > el.clientHeight + 1;
//          }
//
//          function findScrollContainerFromPoint(x, y) {
//            let el = document.elementFromPoint(x, y);
//            while (el && el !== document.documentElement) {
//              if (isScrollable(el)) return el;
//              el = el.parentElement;
//            }
//            return document.scrollingElement || document.documentElement;
//          }
//
//          // ---- touch interception (no wiggle) ----
//          const THRESH_PX = 6; // don’t hijack taps; only take over if user clearly scrolls
//          let tracking = false;
//          let tookOver = false;
//          let startX = 0, startY = 0;
//          let lastY = 0;
//          let scroller = null;
//
//          function resetGesture() {
//            tracking = false;
//            tookOver = false;
//            scroller = null;
//          }
//
//          document.addEventListener("touchstart", (e) => {
//            if (!e.touches || e.touches.length !== 1) { resetGesture(); return; }
//
//            tracking = true;
//            tookOver = false;
//
//            startX = e.touches[0].clientX;
//            startY = e.touches[0].clientY;
//            lastY = startY;
//
//            scroller = findScrollContainerFromPoint(startX, startY);
//          }, { passive: true, capture: true });
//
//          document.addEventListener("touchmove", (e) => {
//            if (!tracking) return;
//            if (!e.touches || e.touches.length !== 1) { resetGesture(); return; }
//
//            const x = e.touches[0].clientX;
//            const y = e.touches[0].clientY;
//
//            const dxTotal = x - startX;
//            const dyTotal = y - startY;
//
//            // Decide if this is a scroll (mostly vertical and beyond threshold)
//            if (!tookOver) {
//              if (Math.abs(dyTotal) < THRESH_PX) return; // still a tap/press
//              if (Math.abs(dyTotal) < Math.abs(dxTotal)) return; // likely horizontal gesture; don’t interfere
//
//              // We are now taking over scrolling
//              tookOver = true;
//              if (firstScrollAt === null) firstScrollAt = now();
//            }
//
//            // Take over: prevent native scroll and apply scaled scroll ourselves
//            e.preventDefault();
//
//            const dy = y - lastY;
//            lastY = y;
//
//            const m = frictionMult();
//            const delta = -dy * m; // finger down -> scroll up
//
//            // scroller can change under finger (dynamic DOM); refresh occasionally
//            if (!scroller) scroller = findScrollContainerFromPoint(x, y);
//
//            scroller.scrollTop += delta;
//          }, { passive: false, capture: true });
//
//          document.addEventListener("touchend", resetGesture, { passive: true, capture: true });
//          document.addEventListener("touchcancel", resetGesture, { passive: true, capture: true });
//
//          console.log("[FrictionMode iOS] injected: grayscale(on-page-time) + touch friction(no pullback)");
//        })();
//        """
//    }
//}
//
//struct ContentView: View {
//    var body: some View {
//        IGWebView()
//            .ignoresSafeArea()
//    }
//}
import SwiftUI
import WebKit
import UIKit

struct IGWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView

    func makeUIView(context: Context) -> WKWebView {
        // --- JS injection ---
        let contentController = WKUserContentController()

        // (Optional) A tiny "parity" script to ensure mobile-friendly viewport behavior.
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

        let frictionGrayScript = WKUserScript(
            source: injectedScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(frictionGrayScript)

        // --- WebView configuration ---
        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.websiteDataStore = .default()

        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)

        webView.allowsBackForwardNavigationGestures = true

        webView.scrollView.bounces = true
        webView.scrollView.alwaysBounceVertical = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        webView.customUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"

        if let url = URL(string: "https://www.instagram.com/") {
            var req = URLRequest(url: url)
            req.cachePolicy = .useProtocolCachePolicy
            webView.load(req)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Injected JavaScript (Grayscale + Scroll Friction)
    private var injectedScript: String {
        return """
        (() => {
          // ===== CONFIG =====
          const GRAY_START_AFTER_SEC = 10;
          const GRAY_RAMP_SEC = 20;

          const FRICTION_START_AFTER_SCROLL_SEC = 10;
          const FRICTION_RAMP_SEC = 20;
          const MIN_MULT = 0.20;

          // When friction is active, manual scrolling can feel "thick".
          // This gain helps match Safari’s baseline feel while still slowing.
          const MANUAL_GAIN = 1.35; // try 1.0–1.8

          const clamp01 = (x) => Math.max(0, Math.min(1, x));
          const now = () => performance.now();

          const pageStart = now();
          let firstScrollAt = null;

          function frictionMult() {
            if (firstScrollAt === null) return 1;
            const t = (now() - firstScrollAt) / 1000;
            if (t < FRICTION_START_AFTER_SCROLL_SEC) return 1;
            const r = clamp01((t - FRICTION_START_AFTER_SCROLL_SEC) / FRICTION_RAMP_SEC);
            const eased = r * r;
            return 1 - eased * (1 - MIN_MULT);
          }

          function grayLevel() {
            const t = (now() - pageStart) / 1000;
            if (t < GRAY_START_AFTER_SEC) return 0;
            return clamp01((t - GRAY_START_AFTER_SEC) / GRAY_RAMP_SEC);
          }

          setInterval(() => {
            const pct = Math.round(grayLevel() * 100);
            if (document.body) document.body.style.filter = `grayscale(${pct}%)`;
          }, 200);

          // ---- scroll container detection ----
          function isScrollable(el) {
            if (!el) return false;
            const s = getComputedStyle(el);
            const oy = s.overflowY;
            return (oy === "auto" || oy === "scroll") && el.scrollHeight > el.clientHeight + 1;
          }

          function findScrollContainerFromPoint(x, y) {
            let el = document.elementFromPoint(x, y);
            while (el && el !== document.documentElement) {
              if (isScrollable(el)) return el;
              el = el.parentElement;
            }
            return document.scrollingElement || document.documentElement;
          }

          // ---- touch interception (keep native speed until friction is active) ----
          const THRESH_PX = 8;
          let tracking = false;
          let tookOver = false;
          let startX = 0, startY = 0;
          let lastY = 0;
          let scroller = null;

          function resetGesture() {
            tracking = false;
            tookOver = false;
            scroller = null;
          }

          document.addEventListener("touchstart", (e) => {
            if (!e.touches || e.touches.length !== 1) { resetGesture(); return; }

            tracking = true;
            tookOver = false;

            startX = e.touches[0].clientX;
            startY = e.touches[0].clientY;
            lastY = startY;

            scroller = null; // choose on takeover (or refresh later)
          }, { passive: true, capture: true });

          document.addEventListener("touchmove", (e) => {
            if (!tracking) return;
            if (!e.touches || e.touches.length !== 1) { resetGesture(); return; }

            const x = e.touches[0].clientX;
            const y = e.touches[0].clientY;

            const dxTotal = x - startX;
            const dyTotal = y - startY;

            // Wait until it’s clearly a vertical scroll gesture
            if (Math.abs(dyTotal) < THRESH_PX) return;
            if (Math.abs(dyTotal) < Math.abs(dxTotal)) return;

            // Mark first scroll gesture time (starts friction timer)
            if (firstScrollAt === null) firstScrollAt = now();

            const m = frictionMult();

            // ✅ If friction is not active yet, DO NOT interfere.
            // This preserves Safari's native speed + momentum.
            if (m >= 0.999) {
              lastY = y;      // keep updated to prevent jump if we later take over
              tookOver = false;
              scroller = null;
              return;
            }

            // ✅ Once friction is active, take over
            if (!tookOver) {
              tookOver = true;
              scroller = findScrollContainerFromPoint(x, y);
              lastY = y;
            }

            e.preventDefault();

            const dy = y - lastY;
            lastY = y;

            const delta = -dy * m * MANUAL_GAIN;

            if (!scroller) scroller = findScrollContainerFromPoint(x, y);
            scroller.scrollTop += delta;
          }, { passive: false, capture: true });

          document.addEventListener("touchend", resetGesture, { passive: true, capture: true });
          document.addEventListener("touchcancel", resetGesture, { passive: true, capture: true });

          console.log("[IG iOS] injected: grayscale + native-first friction");
        })();
        """
    }
}

struct ContentView: View {
    var body: some View {
        IGWebView()
            .ignoresSafeArea()
    }
}
