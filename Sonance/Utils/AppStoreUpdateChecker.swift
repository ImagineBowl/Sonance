//
//  AppStoreUpdateChecker.swift
//  Sonance
//
//  Created by Ahsan Minhas on 18/06/2026.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct AppStoreUpdateInfo: Sendable, Equatable {
    let storeVersion: String
    let appStoreURL: URL
}

enum AppStoreUpdateChecker {
    private static let bundleID = "com.ImagineBowl.Sonance"
    private static let dismissedVersionKey = "AppStoreUpdateChecker.dismissedVersion"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func fetchUpdateInfo() async -> AppStoreUpdateInfo? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID)
        ]

        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode) else {
                return nil
            }

            let lookupResponse = try JSONDecoder().decode(ITunesLookupResponse.self, from: data)
            guard let result = lookupResponse.results.first,
                  let appStoreURL = URL(string: result.trackViewUrl),
                  isStoreVersionNewer(result.version, than: currentVersion) else {
                return nil
            }

            return AppStoreUpdateInfo(storeVersion: result.version, appStoreURL: appStoreURL)
        } catch {
            return nil
        }
    }

    static func isDismissed(_ update: AppStoreUpdateInfo) -> Bool {
        UserDefaults.standard.string(forKey: dismissedVersionKey) == update.storeVersion
    }

    static func dismiss(_ update: AppStoreUpdateInfo) {
        UserDefaults.standard.set(update.storeVersion, forKey: dismissedVersionKey)
    }

    static func openAppStore(for update: AppStoreUpdateInfo) {
        #if canImport(UIKit)
        UIApplication.shared.open(update.appStoreURL)
        #endif
    }

    private static func isStoreVersionNewer(_ storeVersion: String, than currentVersion: String) -> Bool {
        storeVersion.compare(currentVersion, options: .numeric) == .orderedDescending
    }
}

private struct ITunesLookupResponse: Decodable {
    let results: [ITunesAppResult]
}

private struct ITunesAppResult: Decodable {
    let version: String
    let trackViewUrl: String
}
