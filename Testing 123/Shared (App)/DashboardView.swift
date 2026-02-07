//
//  DashboardView.swift
//  Sisyphus
//
//  Main dashboard showing scroll stats and tracked domains
//

import SwiftUI

struct DashboardView: View {
    @ObservedObject var data = SisyphusData.shared
    @State private var refreshTimer: Timer?
    @State private var domainToOpen: String?
    @State private var showInAppBrowser = false

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 24) {
                        // Stats cards
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            StatCard(
                                title: "Today's Scroll",
                                value: data.formatDuration(ms: data.totalScrollTimeToday),
                                subtitle: "across all sites",
                                gradient: [Color(hex: "667eea"), Color(hex: "764ba2")]
                            )
                            StatCard(
                                title: "Time Limit",
                                value: data.scrollLimitMinutes == 0 ? "∞" : "\(data.scrollLimitMinutes) min",
                                subtitle: "per domain",
                                gradient: [Color(hex: "f093fb"), Color(hex: "f5576c")]
                            )
                            StatCard(
                                title: "Tracked Sites",
                                value: "\(data.trackedDomains.count)",
                                subtitle: "domains",
                                gradient: [Color(hex: "4facfe"), Color(hex: "00f2fe")]
                            )
                            StatCard(
                                title: "Friction Mode",
                                value: "ON",
                                subtitle: "after limit",
                                gradient: [Color(hex: "43e97b"), Color(hex: "38f9d7")]
                            )
                        }
                        .padding(.horizontal)

                        // Browse in Sisyphus — open tracked sites inside the app with constraints
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
                        
                        // Per-domain stats
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
                        
                        // Weekly progress placeholder
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Weekly progress")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            HStack(alignment: .bottom, spacing: 8) {
                                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { index, day in
                                    let heights: [CGFloat] = [60, 40, 80, 30, 50, 20, 10]
                                    VStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                                    startPoint: .bottom,
                                                    endPoint: .top
                                                )
                                            )
                                            .frame(height: index < heights.count ? heights[index] : 40)
                                        Text(day)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 140)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.9))
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
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
