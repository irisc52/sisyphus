//
//  DashboardView.swift
//  Sisyphus
//
//  Main dashboard showing scroll stats and tracked domains
//

import SwiftUI
import CoreLocation

struct DashboardView: View {
    @ObservedObject var data = SisyphusData.shared
    @State private var refreshTimer: Timer?
    @State private var domainToOpen: String?
    @State private var showInAppBrowser = false
    @State private var selectedStatIndex = 0

    private func hourAxisLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12a"
        case 6: return "6a"
        case 12: return "12p"
        case 18: return "6p"
        default: return ""
        }
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 12) {
                            HStack(spacing: 0) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        selectedStatIndex = (selectedStatIndex + 3) % 4
                                    }
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .frame(width: 44, height: 200)
                                }
                                .buttonStyle(.plain)

                                TabView(selection: $selectedStatIndex) {
                                    StatCard(
                                        title: "Today's Scroll",
                                        value: data.formatDuration(ms: data.totalScrollTimeToday),
                                        subtitle: "across all sites",
                                        gradient: [Color(hex: "667eea"), Color(hex: "764ba2")]
                                    )
                                    .tag(0)
                                    StatCard(
                                        title: "Time Limit",
                                        value: data.scrollLimitMinutes == 0 ? "∞" : "\(data.scrollLimitMinutes) min",
                                        subtitle: "per domain",
                                        gradient: [Color(hex: "f093fb"), Color(hex: "f5576c")]
                                    )
                                    .tag(1)
                                    StatCard(
                                        title: "Tracked Sites",
                                        value: "\(data.trackedDomains.count)",
                                        subtitle: "domains",
                                        gradient: [Color(hex: "4facfe"), Color(hex: "00f2fe")]
                                    )
                                    .tag(2)
                                    StatCardSitesList(data: data)
                                        .tag(3)
                                }
                                .tabViewStyle(.page(indexDisplayMode: .never))
                                .frame(height: 200)
                                .animation(.easeInOut(duration: 0.5), value: selectedStatIndex)

                                Button {
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        selectedStatIndex = (selectedStatIndex + 1) % 4
                                    }
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .frame(width: 44, height: 200)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)

                            // Custom page dots — higher contrast
                            HStack(spacing: 8) {
                                ForEach(0..<4, id: \.self) { index in
                                    Circle()
                                        .fill(index == selectedStatIndex ? Color.primary : Color.primary.opacity(0.25))
                                        .frame(width: 8, height: 8)
                                        .scaleEffect(index == selectedStatIndex ? 1.2 : 1.0)
                                        .animation(.easeInOut(duration: 0.35), value: selectedStatIndex)
                                }
                            }
                        }

                        // Harsh mode at location — stronger interventions when at this address
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Harsh mode at location", systemImage: "location.fill")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            HarshLocationSection(data: data)
                            Text("When you're at this address and over your limit, friction and darkening are stronger and blur is added.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 12) {
                            Label("Break reminder", systemImage: "clock.badge.exclamationmark")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text("Show full-screen break after")
                                    .font(.subheadline)
                                Spacer()
                                Stepper("\(data.breakOverlayAfterMinutes) min", value: Binding(
                                    get: { data.breakOverlayAfterMinutes },
                                    set: { data.breakOverlayAfterMinutes = min(60, max(1, $0)) }
                                ), in: 1...60)
                                .labelsHidden()
                                Text("\(data.breakOverlayAfterMinutes) min")
                                    .font(.subheadline.monospacedDigit())
                                    .frame(width: 44, alignment: .trailing)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text("In the in-app browser, nothing happens until your Time Limit (per domain) is reached. Then friction, darkening, and popups start. This setting is when the full-screen break appears after that.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        if !data.trackedDomains.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Browse in Sisyphus", systemImage: "safari")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Text("Open these sites inside the app to apply grayscale and scroll friction.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(data.trackedDomains, id: \.self) { domain in
                                    Button {
                                        domainToOpen = domain
                                        showInAppBrowser = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "globe")
                                                .foregroundStyle(.purple)
                                            Text(domain)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            Image(systemName: "arrow.up.forward")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding()
                                        .background(Color(.systemGray6))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        if !data.domainsWithStats.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Today's scroll by site")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                
                                ForEach(data.domainsWithStats, id: \.domain) { item in
                                    HStack {
                                        Image(systemName: "globe")
                                            .foregroundStyle(.purple)
                                            .frame(width: 24, alignment: .center)
                                        Text(item.domain)
                                            .font(.subheadline.weight(.medium))
                                        Spacer()
                                        Text(data.formatDuration(ms: item.timeMs))
                                            .font(.subheadline.monospacedDigit())
                                            .foregroundStyle(.purple)
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Today")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            let bars = data.hourlyProgressBars
                            let scaleMs: Int64 = 60 * 60 * 1000
                            let maxBarHeight: CGFloat = 100
                            GeometryReader { geo in
                                let axisWidth: CGFloat = 32
                                let spacing: CGFloat = 1
                                let chartWidth = geo.size.width - axisWidth - 4
                                let barWidth = max(2, (chartWidth - spacing * 23) / 24)
                                HStack(alignment: .bottom, spacing: 4) {
                                    VStack(alignment: .trailing, spacing: 0) {
                                        ZStack(alignment: .top) {
                                            Color.clear.frame(width: axisWidth, height: maxBarHeight)
                                            Text("60 min")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.tertiary)
                                                .frame(width: axisWidth, alignment: .trailing)
                                                .offset(y: 0)
                                            Text("30")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.tertiary)
                                                .frame(width: axisWidth, alignment: .trailing)
                                                .offset(y: 50)
                                        }
                                        .frame(width: axisWidth, height: maxBarHeight)
                                        Text("0")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.tertiary)
                                            .frame(width: axisWidth, height: 20, alignment: .trailing)
                                    }
                                    .frame(width: axisWidth, height: maxBarHeight + 20)
                                    let chartContentWidth = 24 * barWidth + 23 * spacing
                                    VStack(alignment: .center, spacing: 0) {
                                        HStack(alignment: .bottom, spacing: spacing) {
                                            ForEach(bars) { bar in
                                                let barHeight = bar.scrollMs > 0 ? min(maxBarHeight, CGFloat(bar.scrollMs) / CGFloat(scaleMs) * maxBarHeight) : 0
                                                VStack(spacing: 0) {
                                                    Spacer(minLength: 0)
                                                    RoundedRectangle(cornerRadius: 1)
                                                        .fill(
                                                            LinearGradient(
                                                                colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                                                startPoint: .bottom,
                                                                endPoint: .top
                                                            )
                                                        )
                                                        .frame(width: barWidth, height: barHeight)
                                                }
                                                .frame(width: barWidth, height: maxBarHeight)
                                            }
                                        }
                                        .frame(width: chartContentWidth, height: maxBarHeight)
                                        .background(
                                            Path { p in
                                                let w = chartContentWidth
                                                let h = maxBarHeight
                                                for y in [CGFloat(0), 50, h] {
                                                    p.move(to: CGPoint(x: 0, y: y))
                                                    p.addLine(to: CGPoint(x: w, y: y))
                                                }
                                                for hour in [0, 6, 12, 18, 24] {
                                                    let x = CGFloat(hour) * (barWidth + spacing)
                                                    p.move(to: CGPoint(x: x, y: 0))
                                                    p.addLine(to: CGPoint(x: x, y: h))
                                                }
                                            }
                                            .stroke(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                        )
                                        ZStack(alignment: .leading) {
                                            Color.clear
                                                .frame(width: chartContentWidth, height: 20)
                                            ForEach([0, 6, 12, 18], id: \.self) { hour in
                                                Text(hourAxisLabel(hour))
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize(horizontal: true, vertical: false)
                                                    .position(x: CGFloat(hour) * (barWidth + spacing) + barWidth / 2, y: 10)
                                            }
                                        }
                                        .frame(height: 20)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .offset(x: -10, y: 5)
                            }
                            .frame(height: 120)
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                        
                        // Tips
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Tips", systemImage: "lightbulb.fill")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                TipRow(text: "Resistance increases gradually after \(data.scrollLimitMinutes) minutes")
                                TipRow(text: "Leaving and coming back won't reset the timer (24h window)")
                                TipRow(text: "Try a lower time limit as you build better habits")
                                TipRow(text: "Track multiple sites to see total time across platforms")
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 8)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Sisyphus")
                .navigationBarTitleDisplayMode(.large)
            }
            .onAppear {
                data.refresh()
                refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                    data.refresh()
                }
                RunLoop.main.add(refreshTimer!, forMode: .common)
            }
            .onDisappear {
                refreshTimer?.invalidate()
                refreshTimer = nil
            }
            .fullScreenCover(isPresented: $showInAppBrowser, onDismiss: {
                data.refresh()
            }) {
                Group {
                    if let domain = domainToOpen, let url = URL(string: "https://\(domain)") {
                        InAppBrowserView(url: url, domain: domain)
                            .onDisappear { domainToOpen = nil }
                    }
                }
            }
        } else {
            // Fallback on earlier versions
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let gradient: [Color]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.9))
            Text(value)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Card showing "Today's scroll by site" — per-domain breakdown for the rotating carousel.
struct StatCardSitesList: View {
    @ObservedObject var data: SisyphusData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's scroll by site")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.9))
            if data.domainsWithStats.isEmpty {
                Text("No sites yet")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(data.domainsWithStats.prefix(6), id: \.domain) { item in
                            HStack {
                                Text(item.domain)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                                Text(data.formatDuration(ms: item.timeMs))
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [Color(hex: "667eea"), Color(hex: "764ba2")], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct TipRow: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.purple)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}

struct HarshLocationSection: View {
    @ObservedObject var data: SisyphusData
    @State private var addressInput: String = ""
    @State private var geocodeMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("e.g. 123 Main St, City", text: $addressInput)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.words)
                .onAppear { addressInput = data.harshLocationAddress }
            HStack {
                Button("Save location") {
                    saveAndGeocode()
                }
                .buttonStyle(.borderedProminent)
                if data.harshLocationLat != nil {
                    Button("Clear") {
                        data.harshLocationAddress = ""
                        data.clearHarshLocationCoordinates()
                        addressInput = ""
                        geocodeMessage = nil
                    }
                    .foregroundStyle(.secondary)
                }
            }
            if let msg = geocodeMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(msg.contains("Saved") ? .green : .red)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func saveAndGeocode() {
        let address = addressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { geocodeMessage = "Enter an address"; return }
        data.harshLocationAddress = address
        geocodeMessage = "Geocoding…"
        CLGeocoder().geocodeAddressString(address) { placemarks, error in
            DispatchQueue.main.async {
                if let loc = placemarks?.first?.location {
                    data.setHarshLocationCoordinates(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
                    geocodeMessage = "Saved. Harsh mode will apply when you're near this address."
                } else {
                    geocodeMessage = error?.localizedDescription ?? "Could not find address."
                }
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
