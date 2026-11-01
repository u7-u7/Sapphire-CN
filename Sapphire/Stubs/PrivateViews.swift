//
//  PrivateViews.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

#if !SAPPHIRE_FULL_BUILD
import SwiftUI

private struct UnavailableFeatureView: View {
    let name: String

    var body: some View {
        Text("\(name) is not included in this build.")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SportsSettingsView: View {
    var body: some View { UnavailableFeatureView(name: "Sports") }
}

struct FinanceSettingsView: View {
    var body: some View { UnavailableFeatureView(name: "Finance") }
}

struct AccountSettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)

            Text("账户登录暂不可用")
                .font(.title2.bold())

            Text("当前开源构建未包含账户登录与订阅管理功能。")
                .foregroundStyle(.secondary)

            Text("你正在以访客身份使用 Sapphire-CN，可从左侧选择其他设置。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BetaBlockerView: View {
    var onValidationComplete: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Beta validation is not included in this build.")
                .foregroundColor(.secondary)
            Button("Continue", action: onValidationComplete)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NativePaymentSheetView: View {
    var tier: SubscriptionTier
    var deviceCount: Int
    var isAddingOnly: Bool
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Purchases are not included in this build.")
                .foregroundColor(.secondary)
            Button("Close", action: onDismiss)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum SubscriptionRevocationReason: String {
    case sessionExpired

    var alertMessage: String { "Your session has expired. Please sign in again." }
}

final class ScreenPerception {
    func captureAnnotatedScreen() async -> (NSImage?, [String]) { (nil, []) }
}
#endif
