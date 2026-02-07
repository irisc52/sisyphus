//
//  IGWebView.swift
//  iOS (App)
//
//  Instagram WebView with grayscale + scroll friction
//

import SwiftUI
import WebKit
import UIKit

struct IGWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()

        // Inject JS after the page loads
        let script = WKUserScript(
            source: injectedScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(script)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)

        // Make it feel like a browser
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = true
        webView.scrollView.alwaysBounceVertical = true
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

        // Load Instagram web
        if let url = URL(string: "https://www.instagram.com") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Injected JavaScript (Grayscale + Scroll Friction)
    private var injectedScript: String {
        return """
        (() => {
          // ===== CONFIG =====
          const GRAY_START_AFTER_SEC = 10;  // start grayscale after 10s on page
          const GRAY_RAMP_SEC = 20;         // ramp to full gray over 20s

          const FRICTION_START_AFTER_SCROLL_SEC = 10; // start friction 10s after first real scroll gesture
          const FRICTION_RAMP_SEC = 20;
          const MIN_MULT = 0.20; // aggressive: at max only 20% of motion "sticks"

          const clamp01 = (x) => Math.max(0, Math.min(1, x));
          const now = () => performance.now();

          // Time on page (for grayscale)
          const pageStart = now();

          // Time since first scroll gesture (for friction)
          let firstScrollAt = null;

          function frictionMult() {
            if (firstScrollAt === null) return 1;
            const t = (now() - firstScrollAt) / 1000;
            if (t < FRICTION_START_AFTER_SCROLL_SEC) return 1;
            const r = clamp01((t - FRICTION_START_AFTER_SCROLL_SEC) / FRICTION_RAMP_SEC);
            const eased = r * r; // aggressive
            return 1 - eased * (1 - MIN_MULT);
          }

          // ---- grayscale ----
          function grayLevel() {
            const t = (now() - pageStart) / 1000;
            if (t < GRAY_START_AFTER_SEC) return 0;
            return clamp01((t - GRAY_START_AFTER_SEC) / GRAY_RAMP_SEC);
          }

          setInterval(() => {
            const pct = Math.round(grayLevel() * 100);
            document.documentElement.style.filter = `grayscale(${pct}%)`;
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

          // ---- touch interception (no wiggle) ----
          const THRESH_PX = 6; // don't hijack taps; only take over if user clearly scrolls
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

            scroller = findScrollContainerFromPoint(startX, startY);
          }, { passive: true, capture: true });

          document.addEventListener("touchmove", (e) => {
            if (!tracking) return;
            if (!e.touches || e.touches.length !== 1) { resetGesture(); return; }

            const x = e.touches[0].clientX;
            const y = e.touches[0].clientY;

            const dxTotal = x - startX;
            const dyTotal = y - startY;

            // Decide if this is a scroll (mostly vertical and beyond threshold)
            if (!tookOver) {
              if (Math.abs(dyTotal) < THRESH_PX) return; // still a tap/press
              if (Math.abs(dyTotal) < Math.abs(dxTotal)) return; // likely horizontal gesture; don't interfere

              // We are now taking over scrolling
              tookOver = true;
              if (firstScrollAt === null) firstScrollAt = now();
            }

            // Take over: prevent native scroll and apply scaled scroll ourselves
            e.preventDefault();

            const dy = y - lastY;
            lastY = y;

            const m = frictionMult();
            const delta = -dy * m; // finger down -> scroll up

            // scroller can change under finger (dynamic DOM); refresh occasionally
            if (!scroller) scroller = findScrollContainerFromPoint(x, y);

            scroller.scrollTop += delta;
          }, { passive: false, capture: true });

          document.addEventListener("touchend", resetGesture, { passive: true, capture: true });
          document.addEventListener("touchcancel", resetGesture, { passive: true, capture: true });

          console.log("[FrictionMode iOS] injected: grayscale(on-page-time) + touch friction(no pullback)");
        })();
        """
    }
}

struct IGContentView: View {
    var body: some View {
        IGWebView()
            .ignoresSafeArea()
    }
}
