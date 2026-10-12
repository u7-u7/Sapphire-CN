//
//  SapphireAnalytics.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import FirebaseAnalytics
import FirebaseCrashlytics

@MainActor
enum SapphireAnalytics {
    static var isEnabled: Bool {
        SettingsModel.shared.settings.googleAnalyticsEnabled
    }

    static func bootstrap() {
        guard isEnabled else { return }
        applyCollectionPreference()
    }

    static func applyCollectionPreference() {
        if isEnabled {
            FirebaseBootstrap.configureIfNeeded()
        }
        guard FirebaseBootstrap.isConfigured else { return }
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(isEnabled)
    }

    static func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        guard isEnabled else { return }

        if !FirebaseBootstrap.isConfigured {
            bootstrap()
        }
        guard FirebaseBootstrap.isConfigured else { return }
        Analytics.logEvent(name, parameters: parameters)
    }
}
