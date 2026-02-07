//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Bridges extension ↔ app via App Group. Handles sync and getConfig.
//

import SafariServices
import os.log

private let appGroupID = "group.ICKI.sisyphus"

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let profile: UUID?
        if #available(iOS 17.0, macOS 14.0, *) {
            profile = request?.userInfo?[SFExtensionProfileKey] as? UUID
        } else {
            profile = request?.userInfo?["profile"] as? UUID
        }

        let message: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        let defaults = UserDefaults(suiteName: appGroupID)
        var responsePayload: [String: Any] = ["echo": message ?? NSNull()]

        if let msg = message as? [String: Any], let type = msg["type"] as? String {
            switch type {
            case "syncFromExtension":
                if let trackedDomains = msg["trackedDomains"] as? [String] {
                    defaults?.set(trackedDomains, forKey: "trackedDomains")
                }
                if let scrollData = msg["scrollData"] as? [String: [String: Any]] {
                    var converted: [String: [String: Any]] = [:]
                    for (domain, entry) in scrollData {
                        let totalMs = (entry["totalMs"] as? Int) ?? (entry["totalMs"] as? Double).map { Int($0) } ?? 0
                        let lastResetTimestamp = (entry["lastResetTimestamp"] as? Int) ?? (entry["lastResetTimestamp"] as? Double).map { Int($0) } ?? 0
                        converted[domain] = [
                            "totalMs": totalMs,
                            "lastResetTimestamp": lastResetTimestamp
                        ]
                    }
                    if let encoded = try? JSONSerialization.data(withJSONObject: converted) {
                        defaults?.set(encoded, forKey: "scrollData")
                    }
                }
                if let scrollLimitMs = msg["scrollLimitMs"] as? Int {
                    defaults?.set(Int64(scrollLimitMs), forKey: "scrollLimitMs")
                } else if let scrollLimitMs = msg["scrollLimitMs"] as? Double {
                    defaults?.set(Int64(scrollLimitMs), forKey: "scrollLimitMs")
                }
                responsePayload["ok"] = true

            case "getConfig":
                let domains = defaults?.stringArray(forKey: "trackedDomains") ?? []
                let limitMs = defaults?.object(forKey: "scrollLimitMs") as? Int64
                responsePayload["trackedDomains"] = domains
                responsePayload["scrollLimitMs"] = limitMs ?? (30 * 60 * 1000)
                responsePayload["ok"] = true

            default:
                break
            }
        }

        os_log(.default, "Sisyphus native: processed %@", String(describing: message))

        let response = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [SFExtensionMessageKey: responsePayload]
        } else {
            response.userInfo = ["message": responsePayload]
        }

        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
