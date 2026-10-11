//
//  ContinuityCore.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import SwiftUI

enum ContinuityDeviceType: String, Codable, Sendable {
    case phone, tablet, mac, unknown

    var glyph: String {
        switch self {
        case .phone: "iphone"
        case .tablet: "ipad"
        case .mac: "macbook"
        case .unknown: "questionmark.circle"
        }
    }
}

enum ContinuityCapability: String, Codable, CaseIterable, Sendable {
    case clipboard, notifications, media, status, hotspot, files, handoff
    case mirroring, camera, sidecar, universalControl, sms, scan, sketch
    case audioCast, widgets, externalActivities, microphone
}

enum ContinuityLinkState: String, Equatable {
    case offline, nearby, connected, online

    var isUsable: Bool { self == .connected || self == .online }
}

enum ContinuityNetworkKind: String, Codable {
    case wifi, cellular, none
}

struct ContinuityConnectivitySnapshot: Equatable {
    enum Severity: Equatable {
        case noDevice, healthy, degraded, offline
    }

    var severity: Severity = .noDevice
    var deviceName = ""
    var linkState: ContinuityLinkState = .offline
    var headline = ""
    var detail = ""
    var suggestion: String?
    var bluetoothWarning: String?
    var linkError: String?
    var phoneBatteryPercent: Int?
    var phoneCharging = false
    var phoneNetwork: ContinuityNetworkKind?
    var phoneSSID: String?
    var rssi: Int?
    var isRelayed = false

    var hasDevice: Bool { severity != .noDevice }
    var isIssue: Bool { severity == .degraded || severity == .offline }

    static let none = ContinuityConnectivitySnapshot()
}

struct ContinuityPairedPeer: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var deviceType: ContinuityDeviceType
}

@MainActor
final class ContinuityPeer: ObservableObject, Identifiable {
    nonisolated let record: ContinuityPairedPeer
    nonisolated var id: String { record.id }
    @Published var linkState: ContinuityLinkState = .offline
    @Published var capabilities: Set<ContinuityCapability> = []

    init(record: ContinuityPairedPeer) {
        self.record = record
    }

    var displayName: String { record.name }
    func supports(_ capability: ContinuityCapability) -> Bool { capabilities.contains(capability) }
}

struct ContinuityMediaState: Codable, Equatable {
    var sessionId: String
    var appId: String
    var appName: String
    var title: String
    var artist: String?
    var album: String?
    var isPlaying: Bool
    var positionMs: Int
    var durationMs: Int
    var canNext: Bool
    var canPrev: Bool
    var canSeek: Bool
    var artwork: String?

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appId = try values.decodeIfPresent(String.self, forKey: .appId) ?? ""
        sessionId = try values.decodeIfPresent(String.self, forKey: .sessionId) ?? appId
        appName = try values.decodeIfPresent(String.self, forKey: .appName) ?? appId
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try values.decodeIfPresent(String.self, forKey: .artist)
        album = try values.decodeIfPresent(String.self, forKey: .album)
        isPlaying = try values.decodeIfPresent(Bool.self, forKey: .isPlaying) ?? false
        positionMs = try values.decodeIfPresent(Int.self, forKey: .positionMs) ?? 0
        durationMs = try values.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
        canNext = try values.decodeIfPresent(Bool.self, forKey: .canNext) ?? false
        canPrev = try values.decodeIfPresent(Bool.self, forKey: .canPrev) ?? false
        canSeek = try values.decodeIfPresent(Bool.self, forKey: .canSeek) ?? false
        artwork = try values.decodeIfPresent(String.self, forKey: .artwork)
    }
}

enum ContinuityMediaAction: String, Codable {
    case play, pause, toggle, next, previous, seek, stop
}

enum ContinuityActivitySlotKind: String, Codable {
    case icon, text, progress, timer, image, none
}

struct ContinuityActivitySlot: Codable, Equatable {
    var kind: ContinuityActivitySlotKind
    var text: String?
    var glyph: String?
    var imageDigest: String?
    var tintHex: String?
    var progress: Double?
}

struct ContinuityActivityProgress: Codable, Equatable {
    var current: Int
    var max: Int
    var indeterminate: Bool
}

struct ContinuityExternalActivity: Codable, Equatable, Identifiable {
    var key: String
    var appId: String
    var appName: String
    var title: String
    var text: String?
    var left: ContinuityActivitySlot
    var right: ContinuityActivitySlot
    var progress: ContinuityActivityProgress?

    var id: String { key }
}

struct ContinuityLiveExternalActivity: Identifiable, Equatable {
    var activity: ContinuityExternalActivity
    var peerID: String
    var peerName: String
    var appIcon: NSImage?
    var leftImage: NSImage?
    var rightImage: NSImage?
    var expandedImage: NSImage?
    var lastUpdated: Date

    var id: String { activity.key }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.activity == rhs.activity }
}

struct ContinuityMirroredNotification: Identifiable, Equatable {
    var id: String
}

@MainActor
final class ContinuityNotificationBridge: ObservableObject {
    @Published private(set) var latest: ContinuityMirroredNotification?
    func clearLatest() { latest = nil }
}

@MainActor
final class ContinuityExternalActivityBridge: ObservableObject {
    @Published private(set) var featured: ContinuityLiveExternalActivity?
}

@MainActor
final class ContinuityMediaBridge: ObservableObject {
    @Published private(set) var phoneMedia: ContinuityMediaState?
    @Published private(set) var phoneArtwork: NSImage?
    @Published private(set) var phoneDeviceName: String?
    var shouldSurfacePhoneMedia: Bool { false }
}

final class ContinuityHandoffBridge {
    static let openActionID = "CONTINUITY_OPEN"
    func handleBannerTap() {}
}

@MainActor
final class ContinuityManager: ObservableObject {
    static let shared = ContinuityManager()

    @Published private(set) var peers: [ContinuityPeer] = []
    @Published private(set) var connectivity: ContinuityConnectivitySnapshot = .none

    let notificationBridge = ContinuityNotificationBridge()
    let liveActivityBridge = ContinuityExternalActivityBridge()
    let mediaBridge = ContinuityMediaBridge()
    let handoffBridge = ContinuityHandoffBridge()

    private init() {}

    func startIfEnabled() {}
    func stop() {}
    func openWidgets() {}
    func sendMediaCommand(_ action: ContinuityMediaAction, seekMs: Int? = nil) {}
    func sendFiles(_ urls: [URL], toPeerID peerID: String) {}
    func dismissNotificationOnPhone(peerID: String, key: String) {}
    func invokeNotificationAction(peerID: String, key: String, actionId: String, replyText: String?) {}
}

struct ContinuityNotchDetailView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    var body: some View { EmptyView() }
}

struct ContinuityExternalActivityDetailView: View {
    let bridge: ContinuityExternalActivityBridge
    var body: some View { EmptyView() }
}

enum ContinuityNotchActivityView {
    @ViewBuilder static func left(for snapshot: ContinuityConnectivitySnapshot) -> some View { EmptyView() }
    @ViewBuilder static func right(for snapshot: ContinuityConnectivitySnapshot) -> some View { EmptyView() }
}

enum ContinuityExternalActivityView {
    @ViewBuilder static func left(for activity: ContinuityLiveExternalActivity) -> some View { EmptyView() }
    @ViewBuilder static func right(for activity: ContinuityLiveExternalActivity) -> some View { EmptyView() }
}

enum ContinuityMediaActivityView {
    @ViewBuilder static func left(state: ContinuityMediaState, artwork: NSImage?) -> some View { EmptyView() }
    @ViewBuilder static func right(state: ContinuityMediaState, deviceName: String) -> some View { EmptyView() }
}

struct ContinuityNotificationActivityView: View {
    let entry: ContinuityMirroredNotification
    let bridge: ContinuityNotificationBridge
    @Binding var isHovered: Bool
    var body: some View { EmptyView() }
}

extension Notification.Name {
    static let continuityClipboardReceived = Notification.Name("com.shariq.sapphire.continuity.clipboardReceived")
}
#endif
