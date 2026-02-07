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
    
    private let defaults = UserDefaults.standard
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
    
    init() {
        self.trackedDomains = defaults.stringArray(forKey: trackedDomainsKey) ?? []
        
        if let data = defaults.data(forKey: scrollDataKey),
           let decoded = try? JSONDecoder().decode([String: ScrollEntry].self, from: data) {
            self.scrollData = decoded
        } else {
            self.scrollData = [:]
        }
        
        let limitMs = defaults.object(forKey: scrollLimitMsKey) as? Int64 ?? (30 * 60 * 1000)
        self.scrollLimitMinutes = limitMs > 0 ? Int(limitMs / 60000) : 30
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
}
