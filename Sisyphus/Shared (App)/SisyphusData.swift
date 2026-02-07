//
//  SisyphusData.swift
//  Sisyphus
//
//  Data model and persistence for anti-doomscrolling tracking
//

import Foundation
import Combine

struct ScrollEntry: Codable {
    var totalMs: Int64
    var lastResetTimestamp: Int64
}

struct DomainScrollData: Codable {
    var domain: String
    var totalMs: Int64
    var lastResetTimestamp: Int64
}

class SisyphusData: ObservableObject {
    static let shared = SisyphusData()
    
    private let trackedDomainsKey = "trackedDomains"
    private let scrollDataKey = "scrollData"
    private let scrollLimitMsKey = "scrollLimitMs"
    private let breakOverlayAfterMinutesKey = "breakOverlayAfterMinutes"
    private let harshLocationAddressKey = "harshLocationAddress"
    private let harshLocationLatKey = "harshLocationLat"
    private let harshLocationLonKey = "harshLocationLon"
    private let dailyScrollTotalsKey = "dailyScrollTotals"
    private let hourlyScrollPrefix = "hourlyScroll_"

    /// App Group ID - add in Xcode: Signing & Capabilities → App Groups → group.ICKI.sisyphus
    private static let appGroupID = "group.ICKI.sisyphus"

    /// Use App Group for sync with Safari extension; fallback to standard if not configured
    private var defaults: UserDefaults {
        UserDefaults(suiteName: Self.appGroupID) ?? UserDefaults.standard
    }
    
    private let hours24Ms: Int64 = 24 * 60 * 60 * 1000
    
    @Published var trackedDomains: [String] {
        didSet {
            defaults.set(trackedDomains, forKey: trackedDomainsKey)
        }
    }
    
    @Published var scrollData: [String: ScrollEntry] {
        didSet {
            if let encoded = try? JSONEncoder().encode(scrollData) {
                defaults.set(encoded, forKey: scrollDataKey)
            }
        }
    }
    
    @Published var scrollLimitMinutes: Int {
        didSet {
            let ms = scrollLimitMinutes > 0 ? Int64(scrollLimitMinutes) * 60 * 1000 : 0
            defaults.set(ms, forKey: scrollLimitMsKey)
        }
    }
    
    var scrollLimitMs: Int64 {
        scrollLimitMinutes > 0 ? Int64(scrollLimitMinutes) * 60 * 1000 : 0
    }

    /// Minutes of in-app browsing before the full-screen break overlay appears (1–60).
    @Published var breakOverlayAfterMinutes: Int {
        didSet {
            defaults.set(breakOverlayAfterMinutes, forKey: breakOverlayAfterMinutesKey)
        }
    }

    /// When at this location (after geocode), interventions in the in-app browser are harsher.
    @Published var harshLocationAddress: String {
        didSet { defaults.set(harshLocationAddress, forKey: harshLocationAddressKey) }
    }
    @Published var harshLocationLat: Double?
    @Published var harshLocationLon: Double?

    /// Call after geocoding an address to save coordinates for harsh-mode checks.
    func setHarshLocationCoordinates(lat: Double, lon: Double) {
        harshLocationLat = lat
        harshLocationLon = lon
        defaults.set(lat, forKey: harshLocationLatKey)
        defaults.set(lon, forKey: harshLocationLonKey)
    }

    /// Clear saved harsh location coordinates.
    func clearHarshLocationCoordinates() {
        harshLocationLat = nil
        harshLocationLon = nil
        defaults.removeObject(forKey: harshLocationLatKey)
        defaults.removeObject(forKey: harshLocationLonKey)
    }

    init() {
        let store = UserDefaults(suiteName: Self.appGroupID) ?? UserDefaults.standard
        self.trackedDomains = store.stringArray(forKey: trackedDomainsKey) ?? []

        if let data = store.data(forKey: scrollDataKey),
           let decoded = try? JSONDecoder().decode([String: ScrollEntry].self, from: data) {
            self.scrollData = decoded
        } else {
            self.scrollData = [:]
        }

        let limitMs = store.object(forKey: scrollLimitMsKey) as? Int64 ?? (30 * 60 * 1000)
        self.scrollLimitMinutes = limitMs > 0 ? Int(limitMs / 60000) : 0
        let stored = store.integer(forKey: breakOverlayAfterMinutesKey)
        self.breakOverlayAfterMinutes = (stored >= 1 && stored <= 60) ? stored : 2
        self.harshLocationAddress = store.string(forKey: harshLocationAddressKey) ?? ""
        self.harshLocationLat = store.object(forKey: harshLocationLatKey) as? Double
        self.harshLocationLon = store.object(forKey: harshLocationLonKey) as? Double
    }
    
    func shouldReset(_ timestamp: Int64) -> Bool {
        Int64(Date().timeIntervalSince1970 * 1000) - timestamp >= hours24Ms
    }
    
    func scrollDataWithReset() -> [String: ScrollEntry] {
        var data = scrollData
        var changed = false
        
        for (domain, entry) in data {
            if shouldReset(entry.lastResetTimestamp) {
                data[domain] = ScrollEntry(totalMs: 0, lastResetTimestamp: Int64(Date().timeIntervalSince1970 * 1000))
                changed = true
            }
        }
        
        if changed {
            scrollData = data
        }
        return data
    }
    
    var domainsWithStats: [(domain: String, timeMs: Int64)] {
        let data = scrollDataWithReset()
        return trackedDomains.compactMap { domain in
            guard let entry = data[domain], entry.totalMs > 0 else { return nil }
            return (domain, entry.totalMs)
        }
    }
    
    var totalScrollTimeToday: Int64 {
        let data = scrollDataWithReset()
        return data.values.reduce(0) { $0 + $1.totalMs }
    }

    /// Date string key for today (yyyy-MM-dd) in local timezone.
    private static func todayDateKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    /// Scroll totals per calendar day (date key "yyyy-MM-dd" -> total ms). Persisted for weekly graph.
    private var dailyScrollTotals: [String: Int64] {
        get {
            guard let data = defaults.data(forKey: dailyScrollTotalsKey),
                  let decoded = try? JSONDecoder().decode([String: Int64].self, from: data) else {
                return [:]
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                defaults.set(encoded, forKey: dailyScrollTotalsKey)
            }
        }
    }

    /// Add scroll time to today's daily bucket (for weekly progress) and to current hour (for daily usage).
    private func addToDailyTotal(ms: Int64) {
        let key = Self.todayDateKey()
        var totals = dailyScrollTotals
        totals[key, default: 0] += ms
        dailyScrollTotals = totals
    }

    /// Today's scroll time per hour (0–23). Persisted under key hourlyScroll_yyyy-MM-dd.
    private var todayHourlyScroll: [Int64] {
        get {
            let key = hourlyScrollPrefix + Self.todayDateKey()
            guard let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([Int64].self, from: data),
                  decoded.count == 24 else {
                return Array(repeating: 0, count: 24)
            }
            return decoded
        }
        set {
            let key = hourlyScrollPrefix + Self.todayDateKey()
            if let encoded = try? JSONEncoder().encode(newValue) {
                defaults.set(encoded, forKey: key)
            }
        }
    }

    /// Add scroll time to the current hour's bucket (for daily usage graph).
    private func addToHourlyTotal(ms: Int64) {
        let hour = Calendar.current.component(.hour, from: Date())
        var totals = todayHourlyScroll
        totals[hour] += ms
        todayHourlyScroll = totals
    }

    /// One bar for each hour (0–23): hour index, label (e.g. "12a", "6a", "12p"), and scroll ms.
    struct HourBar: Identifiable {
        let id: Int
        let hour: Int
        let label: String
        let scrollMs: Int64
    }

    /// Usage over today's 24 hours. Scale in UI so 60 minutes = full bar height.
    var hourlyProgressBars: [HourBar] {
        let totals = todayHourlyScroll
        return (0..<24).map { hour in
            let h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
            let ampm = hour < 12 ? "a" : "p"
            let label = "\(h)\(ampm)"
            return HourBar(id: hour, hour: hour, label: label, scrollMs: totals[hour])
        }
    }
    
    func addDomain(_ input: String) -> Bool {
        let normalized = normalizeDomain(input)
        guard let domain = normalized, !domain.isEmpty, !trackedDomains.contains(domain) else {
            return false
        }
        trackedDomains.append(domain)
        return true
    }
    
    func removeDomain(_ domain: String) {
        trackedDomains.removeAll { $0 == domain }
    }
    
    func normalizeDomain(_ input: String) -> String? {
        var domain = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if domain.hasPrefix("https://") { domain = String(domain.dropFirst(8)) }
        else if domain.hasPrefix("http://") { domain = String(domain.dropFirst(7)) }
        if domain.hasPrefix("www.") { domain = String(domain.dropFirst(4)) }
        if let first = domain.split(separator: "/").first {
            domain = String(first)
        }
        return domain.isEmpty ? nil : domain
    }
    
    func formatDuration(ms: Int64) -> String {
        if ms < 60_000 {
            return "\(Int(ms / 1000))s"
        }
        let mins = Int(ms / 60_000)
        let secs = Int((ms % 60_000) / 1000)
        if mins < 60 {
            return "\(mins)m \(secs)s"
        }
        let hours = mins / 60
        let remainMins = mins % 60
        return "\(hours)h \(remainMins)m"
    }

    // MARK: - In-app browser grayscale (seconds per host)
    private func grayscaleKey(host: String) -> String { "grayscale_\(host)" }

    func getGrayscaleSeconds(host: String) -> Int {
        let key = grayscaleKey(host: host)
        return defaults.object(forKey: key) as? Int ?? 0
    }

    func setGrayscaleSeconds(host: String, _ seconds: Int) {
        defaults.set(seconds, forKey: grayscaleKey(host: host))
    }

    /// Apply scroll time reported from in-app browser (same 24h reset logic as extension)
    func applyScrollTimeUpdate(domain: String, additionalMs: Int64) {
        let normalized = normalizeDomain(domain) ?? domain
        guard !normalized.isEmpty else { return }
        let doUpdate = { [weak self] in
            guard let self = self else { return }
            if !self.trackedDomains.contains(normalized) {
                self.trackedDomains.append(normalized)
            }
            var data = self.scrollData
            let entry = data[normalized]
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let newEntry: ScrollEntry
            if entry == nil || self.shouldReset(entry!.lastResetTimestamp) {
                newEntry = ScrollEntry(totalMs: additionalMs, lastResetTimestamp: now)
            } else {
                newEntry = ScrollEntry(totalMs: entry!.totalMs + additionalMs, lastResetTimestamp: entry!.lastResetTimestamp)
            }
            data[normalized] = newEntry
            self.addToDailyTotal(ms: additionalMs)
            self.addToHourlyTotal(ms: additionalMs)
            self.objectWillChange.send()
            self.scrollData = data
        }
        if Thread.isMainThread {
            doUpdate()
        } else {
            DispatchQueue.main.async(execute: doUpdate)
        }
    }

    /// Reload from storage (e.g. when extension has synced new scroll data)
    func refresh() {
        objectWillChange.send()

        trackedDomains = defaults.stringArray(forKey: trackedDomainsKey) ?? []

        if let data = defaults.data(forKey: scrollDataKey),
           let decoded = try? JSONDecoder().decode([String: ScrollEntry].self, from: data) {
            scrollData = decoded
        }

        let limitMs = defaults.object(forKey: scrollLimitMsKey) as? Int64 ?? (30 * 60 * 1000)
        scrollLimitMinutes = limitMs > 0 ? Int(limitMs / 60000) : 0
    }
}
