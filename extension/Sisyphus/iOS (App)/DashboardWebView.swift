//
//  DashboardWebView.swift
//  iOS (App)
//
//  Loads the built dashboard HTML in a WKWebView with chrome.storage polyfill
//

import SwiftUI
import WebKit
import UIKit

private let storageKey = "sisyphus_app_storage"

struct DashboardWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "storageBridge")

        let polyfill = WKUserScript(
            source: storagePolyfill,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(polyfill)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.bounces = true
        webView.isOpaque = true
        webView.backgroundColor = UIColor(white: 0.96, alpha: 1)
        webView.scrollView.backgroundColor = UIColor(white: 0.96, alpha: 1)
        webView.scrollView.refreshControl = UIRefreshControl()
        webView.scrollView.refreshControl?.addTarget(context.coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
        context.coordinator.webView = webView
        context.coordinator.refreshControl = webView.scrollView.refreshControl

        // Load dashboard - try several bundle paths (structure varies by Xcode)
        var htmlURL: URL?
        var readAccess: URL?
        for subdir in ["Resources/Dashboard", "Dashboard", "Shared (App)/Resources/Dashboard", ""] {
            if let url = Bundle.main.url(forResource: "dashboard", withExtension: "html", subdirectory: subdir.isEmpty ? nil : subdir) {
                htmlURL = url
                readAccess = url.deletingLastPathComponent()
                break
            }
        }
        if let url = htmlURL, let dir = readAccess {
            webView.navigationDelegate = context.coordinator
            webView.loadFileURL(url, allowingReadAccessTo: dir)
        } else {
            // Dashboard not in bundle – show helpful message
            let fallback = """
            <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
            <body style="font-family:system-ui;padding:40px;background:#f5f5f5;margin:0;">
            <h1>Dashboard not found</h1>
            <p>Run in Terminal:</p>
            <pre style="background:#333;color:#0f0;padding:16px;border-radius:8px;">cd uiux\nnpm run build:ios</pre>
            <p>Then rebuild in Xcode (⌘R).</p>
            </body></html>
            """
            webView.loadHTMLString(fallback, baseURL: nil)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private var storagePolyfill: String {
        """
        (function() {
          const callbacks = {};
          window.chrome = window.chrome || {};
          window.chrome.storage = window.chrome.storage || {};
          window.chrome.storage.sync = {
            get: function(keys, cb) {
              const id = 'g' + Date.now() + Math.random();
              callbacks[id] = cb;
              window.webkit?.messageHandlers?.storageBridge?.postMessage({ type: 'get', keys: keys, id: id });
            },
            set: function(obj, cb) {
              const id = 's' + Date.now() + Math.random();
              callbacks[id] = cb || function() {};
              window.webkit?.messageHandlers?.storageBridge?.postMessage({ type: 'set', data: obj, id: id });
            }
          };
          window.chrome.storage.onChanged = {
            _listeners: [],
            addListener: function(fn) { this._listeners.push(fn); },
            removeListener: function(fn) {
              this._listeners = this._listeners.filter(function(l) { return l !== fn; });
            }
          };
          window.__storageResponse = function(id, result) {
            if (callbacks[id]) { callbacks[id](result); delete callbacks[id]; }
          };
          window.__storageNotify = function(changes) {
            window.chrome.storage.onChanged._listeners.forEach(function(fn) {
              try { fn(changes, 'sync'); } catch(e) {}
            });
          };
        })();
        """
    }
}

class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var webView: WKWebView?
    var refreshControl: UIRefreshControl?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let id = body["id"] as? String else { return }

        switch type {
        case "get":
            let keys = body["keys"] as? [String] ?? []
            let data = UserDefaults.standard.dictionary(forKey: storageKey) ?? [:]
            var result: [String: Any] = [:]
            let allKeys = ["domains", "timeLimit", "scrollTime", "streaks", "lastActive"]
            let toFetch = keys.isEmpty ? allKeys : keys
            for k in toFetch {
                if let v = data[k] { result[k] = v }
            }
            let json = (try? JSONSerialization.data(withJSONObject: result))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            webView?.evaluateJavaScript("window.__storageResponse('\(id)', \(json))", completionHandler: nil)
        case "set":
            var data = UserDefaults.standard.dictionary(forKey: storageKey) ?? [:]
            if let obj = body["data"] as? [String: Any] {
                var changes: [String: [String: Any]] = [:]
                for (k, v) in obj {
                    changes[k] = ["newValue": v]
                    data[k] = v
                }
                UserDefaults.standard.set(data, forKey: storageKey)
                if let changesJson = (try? JSONSerialization.data(withJSONObject: changes))
                    .flatMap({ String(data: $0, encoding: .utf8) }) {
                    webView?.evaluateJavaScript("window.__storageNotify(\(changesJson))", completionHandler: nil)
                }
            }
            webView?.evaluateJavaScript("window.__storageResponse('\(id)', undefined)", completionHandler: nil)
        default:
            break
        }
    }

    private func showLoadError(in webView: WKWebView, error: Error) {
        let msg = error.localizedDescription
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let fallback = """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body style="font-family:system-ui;padding:40px;background:#f5f5f5;margin:0;">
        <h1>Failed to load dashboard</h1>
        <p style="color:#c00;">\(msg)</p>
        <p>Try: Product → Clean Build Folder, then build again.</p>
        </body></html>
        """
        webView.loadHTMLString(fallback, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showLoadError(in: webView, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showLoadError(in: webView, error: error)
    }

    @objc func refresh(_ sender: UIRefreshControl) {
        webView?.evaluateJavaScript("location.reload()") { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.refreshControl?.endRefreshing()
            }
        }
    }
}

struct DashboardContentView: View {
    var body: some View {
        DashboardWebView()
            .ignoresSafeArea()
    }
}
