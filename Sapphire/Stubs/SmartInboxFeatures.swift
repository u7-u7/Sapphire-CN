//
//  SmartInboxFeatures.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

#if !SAPPHIRE_FULL_BUILD
import Foundation
import Combine

struct OTPEvent: Identifiable, Equatable {
    let id: String
    let code: String
    let source: String
    let title: String
    let body: String
    let date: Date
}

struct ParcelShipment: Identifiable, Equatable, Codable {
    let id: String
    var trackingNumber: String
    var carrier: ParcelCarrier
    var title: String
    var status: String
    var detail: String
    var lastUpdated: Date
    var sourceEmailSubject: String?
    var isDelivered: Bool

    var trackingURL: URL? { carrier.trackingURL(trackingNumber) }
}

enum ParcelCarrier: String, Codable, CaseIterable {
    case ups, fedex, usps, dhl, amazon, unknown

    var displayName: String {
        switch self {
        case .ups: return "UPS"
        case .fedex: return "FedEx"
        case .usps: return "USPS"
        case .dhl: return "DHL"
        case .amazon: return "Amazon"
        case .unknown: return "Carrier"
        }
    }

    var trackingURL: (String) -> URL? { { _ in nil } }
}

final class SmartInboxMonitor: ObservableObject {
    static let shared = SmartInboxMonitor()
    private init() {}

    @Published private(set) var latestOTP: OTPEvent?
    @Published private(set) var activeParcels: [ParcelShipment] = []

    private var consumedOTPs: [String: Date] = [:]

    func presentOTP(code: String, source: String, title: String, body: String) {
        guard !hasConsumedOTP(code), latestOTP?.code != code else { return }
        latestOTP = OTPEvent(
            id: UUID().uuidString,
            code: code,
            source: source,
            title: title,
            body: body,
            date: Date()
        )
    }

    func consumeOTP(_ code: String) {
        // 去重窗口长于通知候选的有效期，防止缓存过期后旧通知再次弹出。
        let now = Date()
        consumedOTPs = consumedOTPs.filter { $0.value > now }
        consumedOTPs[code] = now.addingTimeInterval(600)
    }

    func hasConsumedOTP(_ code: String) -> Bool {
        guard let expiry = consumedOTPs[code] else { return false }
        return expiry > Date()
    }

    func dismissOTP() {
        guard let event = latestOTP else { return }
        consumeOTP(event.code)
        latestOTP = nil
    }
}
#endif
