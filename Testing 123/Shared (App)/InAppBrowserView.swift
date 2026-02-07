//
//  InAppBrowserView.swift
//  Sisyphus
//
//  In-app browser: all interventions in Swift (grayscale, friction, timers, overlays).
//

import SwiftUI
import WebKit
import CoreImage
import CoreLocation

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
                    breakOverlayAfterMinutes: data.breakOverlayAfterMinutes,
                    harshLocationLat: data.harshLocationLat,
                    harshLocationLon: data.harshLocationLon,
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
    let breakOverlayAfterMinutes: Int
    let harshLocationLat: Double?
    let harshLocationLon: Double?
    let onScrollTime: (String, Int64) -> Void
    let onGrayscaleTick: (String, Int) -> Void
    let onRequestClose: () -> Void

    func makeUIViewController(context: Context) -> InAppWebViewController {
        InAppWebViewController(
            url: url,
            domain: domain,
            scrollLimitMs: scrollLimitMs,
            grayscaleSeconds: grayscaleSeconds,
            breakOverlayAfterMinutes: breakOverlayAfterMinutes,
            harshLocationLat: harshLocationLat,
            harshLocationLon: harshLocationLon,
            onScrollTime: onScrollTime,
            onGrayscaleTick: onGrayscaleTick,
            onRequestClose: onRequestClose
        )
    }

    func updateUIViewController(_ uiViewController: InAppWebViewController, context: Context) {}
}

private class InAppWebViewController: UIViewController, WKNavigationDelegate, UIGestureRecognizerDelegate, CLLocationManagerDelegate {
    let url: URL
    let domain: String
    let scrollLimitMs: Int64
    let grayscaleSeconds: Int
    let breakOverlayAfterMinutes: Int
    let harshLocationLat: Double?
    let harshLocationLon: Double?
    let onScrollTime: (String, Int64) -> Void
    let onGrayscaleTick: (String, Int) -> Void
    let onRequestClose: () -> Void
    private var webView: WKWebView?
    /// Native timer: report time every 5s only while this browser view is visible (not backgrounded).
    private var sessionTimeTimer: Timer?
    /// Drives native grayscale overlay and persisted grayscale seconds; only runs when view is visible.
    private var sessionSecondsTimer: Timer?
    private let sessionReportInterval: TimeInterval = 5.0
    private var pageLoadFinished = false
    /// Session grayscale seconds (persisted via onGrayscaleTick); only increases while view is on screen.
    private var currentSessionSeconds: Int = 0
    /// User's time limit in seconds; interventions (friction, darkening, popups) start only after this.
    private var interventionLimitSeconds: Int { limitSecondsFromScrollLimit(scrollLimitMs) }
    /// Ramp duration for darkening after limit (seconds). Shorter when at harsh location.
    private var darkenRampSec: Int { isAtHarshLocation ? 30 : 60 }
    /// Ramp duration for friction after limit (seconds).
    private let frictionRampSec = 20
    /// Min friction multiplier (lower = harsher). Harsher when at harsh location.
    private var frictionMinMult: CGFloat { isAtHarshLocation ? 0.05 : 0.20 }
    private let frictionManualGain: CGFloat = 1.35
    /// Max fade overlay alpha. Stronger when at harsh location.
    private var fadeOverlayMaxAlpha: CGFloat { isAtHarshLocation ? 0.75 : 0.5 }
    /// Max blur overlay alpha after limit. Stronger when at harsh location.
    private var blurOverlayMaxAlpha: CGFloat { isAtHarshLocation ? 0.7 : 0.45 }
    /// Popup tiers: all relative to limit. First popup at limit, then +1min, +2min, then break at limit + breakOverlayAfterMinutes.
    private var tier1Sec: Int { interventionLimitSeconds }
    private var tier2Sec: Int { interventionLimitSeconds + 60 }
    private var tier3Sec: Int { interventionLimitSeconds + 120 }
    private var tier4Sec: Int { interventionLimitSeconds + (breakOverlayAfterMinutes * 60) }

    /// Time limit in seconds from scroll limit. If unlimited (0), use 30 min default so interventions still run.
    private func limitSecondsFromScrollLimit(_ ms: Int64) -> Int {
        let sec = Int(ms / 1000)
        return sec > 0 ? sec : (30 * 60)
    }
    private var firstScrollAt: Date?
    private var appliedTier1 = false, appliedTier2 = false, appliedTier3 = false, appliedTier4 = false
    private var interventionContainer: UIView?
    private var grayscaleFilter: CIFilter?
    /// Black fade overlay after limit.
    private var fadeOverlay: UIView?
    /// Blur overlay after limit (ramps with darkening).
    private var blurOverlay: UIVisualEffectView?
    /// When true, user is at/near the harsh-location address; interventions are stronger.
    private var isAtHarshLocation = false
    private let harshLocationRadiusMeters: Double = 150
    private var locationManager: CLLocationManager?

    init(url: URL, domain: String, scrollLimitMs: Int64, grayscaleSeconds: Int,
         breakOverlayAfterMinutes: Int,
         harshLocationLat: Double?,
         harshLocationLon: Double?,
         onScrollTime: @escaping (String, Int64) -> Void, onGrayscaleTick: @escaping (String, Int) -> Void,
         onRequestClose: @escaping () -> Void) {
        self.url = url
        self.domain = domain
        self.scrollLimitMs = scrollLimitMs
        self.grayscaleSeconds = grayscaleSeconds
        self.breakOverlayAfterMinutes = min(60, max(1, breakOverlayAfterMinutes))
        self.harshLocationLat = harshLocationLat
        self.harshLocationLon = harshLocationLon
        self.onScrollTime = onScrollTime
        self.onGrayscaleTick = onGrayscaleTick
        self.onRequestClose = onRequestClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()

        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: Self.viewportScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        contentController.addUserScript(WKUserScript(
            source: Self.scrollBridgeScript,
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

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleFrictionPan(_:)))
        pan.delegate = self
        wv.addGestureRecognizer(pan)
        wv.scrollView.panGestureRecognizer.require(toFail: pan)

        currentSessionSeconds = grayscaleSeconds

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.frame = view.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blur.alpha = blurAlpha(for: currentSessionSeconds)
        blur.isUserInteractionEnabled = false
        view.addSubview(blur)
        blurOverlay = blur

        let fade = UIView(frame: view.bounds)
        fade.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        fade.backgroundColor = .black
        fade.alpha = fadeAlpha(for: currentSessionSeconds)
        fade.isUserInteractionEnabled = false
        view.addSubview(fade)
        fadeOverlay = fade

        startHarshLocationCheckIfNeeded()
        applyNativeGrayscale()

        let container = InterventionContainerView(frame: view.bounds)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(container)
        interventionContainer = container

        var req = URLRequest(url: url)
        req.cachePolicy = .useProtocolCachePolicy
        wv.load(req)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if pageLoadFinished { startSessionTimers() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopSessionTimers()
    }

    /// Grayscale/fade: 0 until user's limit, then ramps over darkenRampSec.
    private func grayscaleIntensity(for seconds: Int) -> CGFloat {
        if seconds < interventionLimitSeconds { return 0 }
        return CGFloat(min(1, Double(seconds - interventionLimitSeconds) / Double(darkenRampSec)))
    }

    private func fadeAlpha(for seconds: Int) -> CGFloat {
        let intensity = grayscaleIntensity(for: seconds)
        return fadeOverlayMaxAlpha * intensity
    }

    /// Blur ramps after limit (same curve as darkening).
    private func blurAlpha(for seconds: Int) -> CGFloat {
        let intensity = grayscaleIntensity(for: seconds)
        return blurOverlayMaxAlpha * intensity
    }

    private func startHarshLocationCheckIfNeeded() {
        guard let lat = harshLocationLat, let lon = harshLocationLon else { return }
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
        locationManager = manager
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, let lat = harshLocationLat, let lon = harshLocationLon else { return }
        let harsh = CLLocation(latitude: lat, longitude: lon)
        let distance = loc.distance(from: harsh)
        let radius = harshLocationRadiusMeters
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isAtHarshLocation = distance <= radius
            self.applyNativeGrayscale()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func applyNativeGrayscale() {
        let intensity = grayscaleIntensity(for: currentSessionSeconds)
        fadeOverlay?.alpha = fadeAlpha(for: currentSessionSeconds)
        blurOverlay?.alpha = blurAlpha(for: currentSessionSeconds)
        guard let wv = webView else { return }
        if intensity <= 0 {
            wv.layer.compositingFilter = nil
            return
        }
        if grayscaleFilter == nil {
            grayscaleFilter = CIFilter(name: "CIColorMonochrome")
            grayscaleFilter?.setValue(CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1), forKey: "inputColor")
        }
        grayscaleFilter?.setValue(intensity, forKey: "inputIntensity")
        wv.layer.compositingFilter = grayscaleFilter
    }

    /// No friction until session exceeds user's limit; then ramps over frictionRampSec.
    private func frictionMultiplier() -> CGFloat {
        if currentSessionSeconds < interventionLimitSeconds { return 1 }
        let secondsOverLimit = currentSessionSeconds - interventionLimitSeconds
        if secondsOverLimit <= 0 { return 1 }
        let t = min(1.0, Double(secondsOverLimit) / Double(frictionRampSec))
        let ramp = t * t
        return 1 - ramp * (1 - frictionMinMult)
    }

    @objc private func handleFrictionPan(_ gesture: UIPanGestureRecognizer) {
        guard let wv = webView else { return }
        switch gesture.state {
        case .began:
            if firstScrollAt == nil { firstScrollAt = Date() }
        case .changed:
            let translation = gesture.translation(in: view)
            gesture.setTranslation(.zero, in: view)
            let mult = frictionMultiplier()
            let dy = -translation.y * mult * frictionManualGain
            let js = "window.__SISYPHUS_SCROLL_BY__ && window.__SISYPHUS_SCROLL_BY__(\(dy));"
            wv.evaluateJavaScript(js, completionHandler: nil)
        case .ended, .cancelled:
            break
        default:
            break
        }
    }

    private func startSessionTimers() {
        stopSessionTimers()
        let domain = self.domain
        let report: (String, Int64) -> Void = onScrollTime
        let reportMs = Int64(sessionReportInterval * 1000)

        sessionTimeTimer = Timer.scheduledTimer(withTimeInterval: sessionReportInterval, repeats: true) { [weak self] _ in
            guard self != nil else { return }
            DispatchQueue.main.async { report(domain, reportMs) }
        }
        RunLoop.main.add(sessionTimeTimer!, forMode: .common)
        DispatchQueue.main.async { report(domain, reportMs) }

        sessionSecondsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.currentSessionSeconds += 1
                self.onGrayscaleTick(domain, self.currentSessionSeconds)
                self.applyNativeGrayscale()
                self.applyInterventionTiers()
            }
        }
        RunLoop.main.add(sessionSecondsTimer!, forMode: .common)
    }

    private func stopSessionTimers() {
        sessionTimeTimer?.invalidate()
        sessionTimeTimer = nil
        sessionSecondsTimer?.invalidate()
        sessionSecondsTimer = nil
    }

    private func applyInterventionTiers() {
        let sec = currentSessionSeconds
        let minutes = Double(sec) / 60
        guard let container = interventionContainer else { return }

        if sec >= tier4Sec && !appliedTier4 {
            appliedTier4 = true
            addBreakOverlay(minutes: minutes, to: container)
        } else if sec >= tier3Sec && !appliedTier3 {
            appliedTier3 = true
            addVignette(to: container)
            addBlurOverlay(to: container)
        } else if sec >= tier2Sec && !appliedTier2 {
            appliedTier2 = true
            addLifeClock(minutes: minutes, to: container)
            addRegretQuote(to: container)
        } else if sec >= tier1Sec && !appliedTier1 {
            appliedTier1 = true
            addOpportunityCost(to: container)
        }
    }

    private func addVignette(to container: UIView) {
        let v = VignetteView(frame: container.bounds)
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.isUserInteractionEnabled = false
        v.layer.name = "sisyphus_vignette"
        v.alpha = 0
        container.addSubview(v)
        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseOut) { v.alpha = 1 }
    }

    private func addBlurOverlay(to container: UIView) {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.frame = container.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blur.alpha = 0
        blur.isUserInteractionEnabled = false
        blur.layer.name = "sisyphus_blur"
        container.addSubview(blur)
        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseOut) { blur.alpha = 0.3 }
    }

    private func addLifeClock(minutes: Double, to container: UIView) {
        let card = SisyphusPopupCard(gradientColors: Self.purpleGradient)
        card.layer.name = "sisyphus_lifeclock"
        card.translatesAutoresizingMaskIntoConstraints = false
        card.alpha = 0
        card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)

        let icon = UIImageView(image: UIImage(systemName: "clock.badge.exclamationmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)))
        icon.tintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.text = minutes >= 60
            ? String(format: "%.1f h", minutes / 60)
            : "\(Int(minutes)) min"
        valueLabel.font = .systemFont(ofSize: 20, weight: .bold)
        valueLabel.textColor = .white

        let subtitleLabel = UILabel()
        let pct = (minutes / 1440) * 100
        subtitleLabel.text = pct < 0.1 ? "Less than 0.1% of your day" : String(format: "%.1f%% of your day", pct)
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.9)

        let hintLabel = UILabel()
        hintLabel.text = "You'll never get this back"
        hintLabel.font = .systemFont(ofSize: 11, weight: .regular)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.8)

        let stack = UIStackView(arrangedSubviews: [icon, valueLabel, subtitleLabel, hintLabel])
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(stack)
        container.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        container.layoutIfNeeded()
        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseOut) {
            card.alpha = 1
            card.transform = .identity
        }
    }

    private static let regretQuotes = [
        "Is this really what you want to be doing?",
        "Your future self will wish you stopped",
        "Every scroll is a choice",
        "What could you be creating instead?",
        "This content will be forgotten tomorrow",
        "Your attention is worth more than this",
        "Nothing new is coming",
        "You're trading time for distraction"
    ]

    private func addRegretQuote(to container: UIView) {
        let card = SisyphusPopupCard(gradientColors: Self.pinkGradient)
        card.layer.name = "sisyphus_quote"
        card.translatesAutoresizingMaskIntoConstraints = false
        card.alpha = 0
        card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)

        let icon = UIImageView(image: UIImage(systemName: "lightbulb.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)))
        icon.tintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false

        let quoteLabel = UILabel()
        quoteLabel.text = Self.regretQuotes.randomElement()
        quoteLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        quoteLabel.textColor = .white
        quoteLabel.numberOfLines = 0
        quoteLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [icon, quoteLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(stack)
        container.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ])
        container.layoutIfNeeded()
        UIView.animate(withDuration: 0.45, delay: 0, options: .curveEaseOut) {
            card.alpha = 1
            card.transform = .identity
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak card] in
            UIView.animate(withDuration: 0.3) { card?.alpha = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { card?.removeFromSuperview() }
        }
    }

    private static let opportunityAlts = [
        "You could have read 10 pages",
        "You could have learned 20 new words",
        "You could have done 100 pushups",
        "You could have meditated",
        "You could have called a friend",
        "You could have written a page",
        "You could have practiced an instrument",
        "You could have cooked a meal"
    ]

    private func addOpportunityCost(to container: UIView) {
        let card = SisyphusPopupCard(gradientColors: Self.blueGradient)
        card.layer.name = "sisyphus_opportunity"
        card.translatesAutoresizingMaskIntoConstraints = false
        card.alpha = 0
        card.transform = CGAffineTransform(translationX: 0, y: 24)

        let icon = UIImageView(image: UIImage(systemName: "sparkles", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)))
        icon.tintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "Instead of this…"
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white

        let altLabel = UILabel()
        altLabel.text = Self.opportunityAlts.randomElement()
        altLabel.font = .systemFont(ofSize: 15, weight: .medium)
        altLabel.textColor = UIColor.white.withAlphaComponent(0.95)
        altLabel.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, altLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(stack)
        container.addSubview(card)
        NSLayoutConstraint.activate([
            card.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        container.layoutIfNeeded()
        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseOut) {
            card.alpha = 1
            card.transform = .identity
        }
    }

    private func addBreakOverlay(minutes: Double, to container: UIView) {
        let overlay = SisyphusGradientOverlay(colors: Self.purpleGradient)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.layer.name = "sisyphus_break"
        overlay.alpha = 0
        container.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let iconView = UIImageView(image: UIImage(systemName: "clock.badge.exclamationmark.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 56, weight: .medium)))
        iconView.tintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "Time for a break"
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        let minutesLabel = UILabel()
        minutesLabel.text = "You've been here for \(Int(minutes)) minutes"
        minutesLabel.font = .systemFont(ofSize: 16, weight: .medium)
        minutesLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        minutesLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Your brain craves novelty, but endless scrolling isn't helping."
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let closeBtn = UIButton(type: .system)
        closeBtn.setTitle("Close & leave", for: .normal)
        closeBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        closeBtn.layer.cornerRadius = 14
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.addTarget(self, action: #selector(breakOverlayCloseTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, minutesLabel, subtitleLabel, closeBtn])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.setCustomSpacing(24, after: subtitleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -32),
            closeBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            closeBtn.heightAnchor.constraint(equalToConstant: 50)
        ])
        container.layoutIfNeeded()
        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseOut) {
            overlay.alpha = 1
        }
    }

    @objc private func breakOverlayCloseTapped() {
        interventionContainer?.subviews.filter { $0.layer.name == "sisyphus_break" }.forEach { $0.removeFromSuperview() }
        onRequestClose()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(Self.scrollBridgeScript, completionHandler: nil)
        pageLoadFinished = true
        startSessionTimers()
    }

    deinit {
        stopSessionTimers()
    }

    // MARK: - Minimal JS (viewport + scroll bridge for native friction)
    private static var viewportScript: String {
        """
        (function(){
          try {
            var meta = document.querySelector('meta[name="viewport"]');
            if (!meta) {
              meta = document.createElement('meta');
              meta.name = 'viewport';
              document.head.appendChild(meta);
            }
            meta.content = 'width=device-width, initial-scale=1.0, viewport-fit=cover';
          } catch (e) {}
        })();
        """
    }

    private static var scrollBridgeScript: String {
        """
        (function(){
          window.__SISYPHUS_SCROLL_BY__ = function(dy) {
            try {
              var el = document.scrollingElement || document.documentElement;
              if (el) el.scrollTop = (el.scrollTop || 0) + dy;
            } catch (e) {}
          };
        })();
        """
    }
}

/// Container for intervention overlays; passes touches through to the web view unless they hit an interactive subview (e.g. break overlay button).
/// Gradient colors matching dashboard StatCards
private extension InAppWebViewController {
    static var purpleGradient: [UIColor] {
        [UIColor(red: 102/255, green: 126/255, blue: 234/255, alpha: 1),
         UIColor(red: 118/255, green: 75/255, blue: 162/255, alpha: 1)]
    }
    static var pinkGradient: [UIColor] {
        [UIColor(red: 240/255, green: 147/255, blue: 251/255, alpha: 1),
         UIColor(red: 245/255, green: 87/255, blue: 108/255, alpha: 1)]
    }
    static var blueGradient: [UIColor] {
        [UIColor(red: 79/255, green: 172/255, blue: 254/255, alpha: 1),
         UIColor(red: 0, green: 242/255, blue: 254/255, alpha: 1)]
    }
}

private final class SisyphusGradientOverlay: UIView {
    private let gradientLayer = CAGradientLayer()

    init(colors: [UIColor]) {
        super.init(frame: .zero)
        gradientLayer.colors = colors.map { $0.cgColor }
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradientLayer, at: 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
}

private final class SisyphusPopupCard: UIView {
    private let gradientLayer = CAGradientLayer()

    init(gradientColors: [UIColor]) {
        super.init(frame: .zero)
        gradientLayer.colors = gradientColors.map { $0.cgColor }
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradientLayer, at: 0)
        layer.cornerRadius = 16
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
}

private final class InterventionContainerView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in subviews.reversed() {
            guard subview.isUserInteractionEnabled, !subview.isHidden, subview.alpha > 0.01 else { continue }
            let pt = convert(point, to: subview)
            if subview.bounds.contains(pt), let hit = subview.hitTest(pt, with: event) {
                return hit
            }
        }
        return nil
    }
}

private final class VignetteView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }
    override init(frame: CGRect) {
        super.init(frame: frame)
        gradientLayer.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.7).cgColor]
        gradientLayer.locations = [0.3, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
