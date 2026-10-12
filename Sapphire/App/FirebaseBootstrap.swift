//
//  FirebaseBootstrap.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import FirebaseAppCheck
import FirebaseCore
import Foundation

@MainActor
enum FirebaseBootstrap {
    private(set) static var isConfigured = false

    private static let hasUsableConfiguration: Bool = {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url) as? [String: Any],
              let apiKey = values["API_KEY"] as? String, !apiKey.isEmpty,
              let projectID = values["PROJECT_ID"] as? String, !projectID.isEmpty,
              projectID != "sapphire-stub",
              let appID = values["GOOGLE_APP_ID"] as? String, !appID.isEmpty,
              appID != "1:000000000000:ios:0000000000000000" else {
            return false
        }
        return true
    }()

    static func configureIfNeeded() {
        // Public builds ship a placeholder plist; Firebase rejects it before onboarding can appear.
        guard !isConfigured, hasUsableConfiguration else { return }
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
        #endif
        FirebaseApp.configure()
        isConfigured = true
    }
}
