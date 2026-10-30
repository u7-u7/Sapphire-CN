//
//  UpdateChecker.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI
import AppKit
import CryptoKit
import Network
import Darwin
import Security
@preconcurrency import UserNotifications

let currentAppVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"

enum SapphireUpdateSource {
    static let repositoryURL = URL(string: "https://github.com/u7-u7/Sapphire-CN")!
    static let releasesURL = repositoryURL.appendingPathComponent("releases")
    // 发布时由真实 GitHub Release 生成此清单，经 CDN 分发，不消耗用户的未登录 API 配额。
    static let metadataURL = URL(string: "https://raw.githubusercontent.com/u7-u7/Sapphire-CN/main/updates/releases.json")!
    static let bundleIdentifier = "com.cshariq.sapphire"

    static var currentReleaseVersion: String {
        releaseVersion(in: .main) ?? "\(currentAppVersion)-cn.0-preview"
    }

    static func releaseVersion(in bundle: Bundle?) -> String? {
        guard let value = bundle?.object(forInfoDictionaryKey: "SapphireCNReleaseVersion") as? String,
              isCNVersion(value) else { return nil }
        return value
    }

    static func isCNVersion(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+(?:\.[0-9]+){1,2}-cn\.[0-9]+(?:-preview)?$"#,
                    options: .regularExpression) != nil
    }

    static func isReleaseAssetURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "github.com"
            && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443)
            && url.path.hasPrefix("/u7-u7/Sapphire-CN/releases/download/")
    }
}

enum AppVersionOrdering {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = ParsedVersion(lhs)
        let b = ParsedVersion(rhs)

        let coreCount = max(a.core.count, b.core.count)
        for index in 0..<coreCount {
            let left = index < a.core.count ? a.core[index] : "0"
            let right = index < b.core.count ? b.core[index] : "0"
            let result = compareNumericComponents(left, right)
            if result != .orderedSame { return result }
        }

        return comparePrerelease(a.prerelease, b.prerelease)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    fileprivate static func compareSapphireMarketing(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = ParsedVersion(lhs)
        let b = ParsedVersion(rhs)

        let majorResult = compareNumericComponents(a.core.first ?? "0", b.core.first ?? "0")
        if majorResult != .orderedSame { return majorResult }

        let minorResult = compareDecimalFractions(
            a.core.count > 1 ? a.core[1] : "0",
            b.core.count > 1 ? b.core[1] : "0"
        )
        if minorResult != .orderedSame { return minorResult }

        let coreCount = max(a.core.count, b.core.count)
        if coreCount > 2 {
            for index in 2..<coreCount {
                let left = index < a.core.count ? a.core[index] : "0"
                let right = index < b.core.count ? b.core[index] : "0"
                let result = compareNumericComponents(left, right)
                if result != .orderedSame { return result }
            }
        }

        return comparePrerelease(a.prerelease, b.prerelease)
    }

    private static func comparePrerelease(_ lhs: [String]?, _ rhs: [String]?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case let (left?, right?):
            let count = max(left.count, right.count)
            for index in 0..<count {
                guard index < left.count else { return .orderedAscending }
                guard index < right.count else { return .orderedDescending }
                let lhsToken = left[index]
                let rhsToken = right[index]
                if lhsToken == rhsToken { continue }
                let lhsIsNumeric = lhsToken.allSatisfy(\.isNumber)
                let rhsIsNumeric = rhsToken.allSatisfy(\.isNumber)
                if lhsIsNumeric, rhsIsNumeric {
                    return compareNumericComponents(lhsToken, rhsToken)
                }
                if lhsIsNumeric { return .orderedAscending }
                if rhsIsNumeric { return .orderedDescending }
                return lhsToken.compare(rhsToken, options: [.caseInsensitive, .numeric])
            }
            return .orderedSame
        }
    }

    private static func compareNumericComponents(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = normalizedNumericComponent(lhs)
        let right = normalizedNumericComponent(rhs)
        if left.count != right.count {
            return left.count > right.count ? .orderedDescending : .orderedAscending
        }
        return left.compare(right)
    }

    private static func compareDecimalFractions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        let left = lhs.padding(toLength: count, withPad: "0", startingAt: 0)
        let right = rhs.padding(toLength: count, withPad: "0", startingAt: 0)
        return left.compare(right)
    }

    private static func normalizedNumericComponent(_ value: String) -> String {
        let trimmed = value.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    private struct ParsedVersion {
        let core: [String]
        let prerelease: [String]?

        init(_ raw: String) {
            var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if (value.hasPrefix("v") || value.hasPrefix("V")),
               value.dropFirst().first?.isNumber == true {
                value.removeFirst()
            }
            if let firstDigit = value.firstIndex(where: \.isNumber), firstDigit != value.startIndex {
                value = String(value[firstDigit...])
            }
            value = String(value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0])

            let pieces = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let coreText = String(pieces[0])
            var suffix = pieces.count > 1 ? String(pieces[1]) : nil
            var parsedCore: [String] = []
            for component in coreText.split(separator: ".", omittingEmptySubsequences: false) {
                let digits = component.prefix(while: \.isNumber)
                parsedCore.append(digits.isEmpty ? "0" : String(digits))
                let trailing = component.dropFirst(digits.count)
                if !trailing.isEmpty {
                    suffix = [String(trailing), suffix].compactMap { $0 }.joined(separator: ".")
                }
            }
            core = parsedCore.isEmpty ? ["0"] : parsedCore
            let tokens = suffix?
                .split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "_" })
                .map { String($0).lowercased() }
            prerelease = tokens?.isEmpty == false ? tokens : nil
        }
    }
}

enum SapphireVersionOrdering {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        AppVersionOrdering.compareSapphireMarketing(lhs, rhs)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }
}

struct GitHubReleaseAsset: Codable, Equatable, Sendable {
    let name: String
    let browserDownloadUrl: URL
    let size: Int64?
    let digest: String?
    let contentType: String?
    enum CodingKeys: String, CodingKey {
        case name, size, digest
        case browserDownloadUrl = "browser_download_url"
        case contentType = "content_type"
    }
}

struct GitHubRelease: Codable {
    let name: String?
    let tagName: String
    let body: String?
    let htmlUrl: String?
    let prerelease: Bool
    let draft: Bool
    let publishedAt: String?
    let assets: [GitHubReleaseAsset]
    enum CodingKeys: String, CodingKey {
        case name, tagName = "tag_name", body, htmlUrl = "html_url", prerelease, draft, assets
        case publishedAt = "published_at"
    }

    var marketingVersion: String {
        let cleanTag = Self.cleanVersionLabel(tagName)
        if cleanTag.contains(where: \.isNumber) {
            return cleanTag
        }
        let fromName = Self.cleanVersionLabel(name ?? "")
        if !fromName.isEmpty { return fromName }
        return cleanTag
    }

    private static func cleanVersionLabel(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if (value.hasPrefix("v") || value.hasPrefix("V")), value.dropFirst().first?.isNumber == true {
            value.removeFirst()
        }
        return value
    }
}

enum UpdateStatus: Equatable {
    case checking
    case upToDate
    case available(version: String, asset: GitHubReleaseAsset)
    case downloading(progress: Double)
    case downloaded(path: URL)
    case installing
    case error(String)

    var isUpdateAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

private struct PersistedAvailableUpdate: Codable {
    let version: String
    let asset: GitHubReleaseAsset
}

private struct FetchedGitHubReleases {
    let releases: [GitHubRelease]
    let usedCache: Bool
    let retryNotBefore: Date?
}

private struct UpdateArchiveTotals {
    let entryCount: Int
    let uncompressedBytes: Int64
    let compressedBytes: Int64
}

private enum PrivilegedUpdateInstallOutcome: Sendable {
    case success
    case failure(String)
}

private final class UpdateInstallContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}

private enum UpdateMetadataError: LocalizedError {
    case invalidResponse
    case insecureRedirect
    case httpStatus(Int)
    case rateLimited(Date?)
    case responseTooLarge
    case emptyCache
    case invalidMetadata
    case noEligibleRelease
    case noEligibleAsset

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The update server returned an invalid response."
        case .insecureRedirect: return "The update server redirected to an untrusted address."
        case .httpStatus(let status): return "The update server returned HTTP \(status)."
        case .rateLimited(let retry):
            if let retry { return "GitHub rate-limited update checks. Retrying \(retry.formatted(date: .omitted, time: .shortened))." }
            return "GitHub rate-limited update checks. Sapphire will retry automatically."
        case .responseTooLarge: return "The update metadata was unexpectedly large."
        case .emptyCache: return "No cached update information is available."
        case .invalidMetadata: return "The update information could not be verified."
        case .noEligibleRelease: return "No release is available for the selected channel."
        case .noEligibleAsset: return "This release does not include a trusted Sapphire ZIP for this Mac."
        }
    }
}

@MainActor
class UpdateChecker: NSObject, ObservableObject, @preconcurrency URLSessionDownloadDelegate {
    static let shared = UpdateChecker()

    @Published var status: UpdateStatus = .upToDate
    @Published var releaseNotes: String?
    @Published var releaseNotesVersion: String?
    @Published var releaseNotesURL: URL?
    @Published private(set) var lastCheckAttemptAt: Date?
    @Published private(set) var lastSuccessfulCheckAt: Date?
    @Published private(set) var nextScheduledCheckAt: Date?
    @Published private(set) var lastCheckError: String?
    @Published private(set) var isUsingCachedReleaseData = false
    private var downloadTask: URLSessionDownloadTask?
    private var downloadSession: URLSession?
    private var downloadedAssetPath: URL?
    private var pendingDownloadAsset: GitHubReleaseAsset?
    private var pendingDownloadVersion: String?
    private var downloadPolicyFailure: String?
    private var downloadGeneration: UInt64 = 0
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var initialCheckWorkItem: DispatchWorkItem?
    private var networkMonitor: NWPathMonitor?
    private let networkMonitorQueue = DispatchQueue(label: "com.cshariq.sapphire.update-network", qos: .utility)
    private var periodicCheckInterval: TimeInterval = 5 * 60 * 60
    // 换源后不能从上游缓存恢复候选、ETag 或旧检查调度。
    private let persistedAvailableUpdateKey = "SapphireCNFeedV1PersistedAvailableUpdate"
    private let releasesCacheKey = "SapphireCNFeedV1ReleasesCache"
    private let releasesCacheETagKey = "SapphireCNFeedV1ReleasesCacheETag"
    private let releasesCacheDateKey = "SapphireCNFeedV1ReleasesCacheDate"
    private let lastSuccessfulCheckKey = "SapphireCNFeedV1UpdateLastSuccessfulCheck"
    private let nextScheduledCheckKey = "SapphireCNFeedV1UpdateNextScheduledCheck"
    private let failureCountKey = "SapphireCNFeedV1UpdateFailureCount"
    private let lastNotifiedUpdateVersionKey = "SapphireCNFeedV1LastNotifiedUpdateVersion"
    private let maximumMetadataBytes = 5 * 1_024 * 1_024
    nonisolated private static let maximumDownloadBytes: Int64 = 1_024 * 1_024 * 1_024
    nonisolated private static let maximumArchiveListingBytes = 5 * 1_024 * 1_024
    nonisolated private static let maximumArchiveTotalsBytes = 64 * 1_024
    nonisolated private static let maximumArchiveEntryCount = 100_000
    nonisolated private static let maximumExpandedArchiveBytes: Int64 = 4 * 1_024 * 1_024 * 1_024
    nonisolated private static let maximumArchiveCompressionRatio = 200.0
    private var consecutiveFailures = 0
    private var lastFailureWasRateLimit = false

    private override init() {
        super.init()
        lastSuccessfulCheckAt = UserDefaults.standard.object(forKey: lastSuccessfulCheckKey) as? Date
        nextScheduledCheckAt = UserDefaults.standard.object(forKey: nextScheduledCheckKey) as? Date
        consecutiveFailures = UserDefaults.standard.integer(forKey: failureCountKey)
        restorePersistedAvailableUpdateIfNeeded()
    }

    private func applyStatus(_ newStatus: UpdateStatus) {
        guard status != newStatus else { return }
        status = newStatus

        switch newStatus {
        case .available(let version, let asset):
            persistAvailableUpdate(version: version, asset: asset)
            if UserDefaults.standard.string(forKey: lastNotifiedUpdateVersionKey) != version {
                UserDefaults.standard.set(version, forKey: lastNotifiedUpdateVersionKey)
                NotificationCenter.default.post(name: .sapphireUpdateAvailable, object: version)
                postUpdateAvailableUserNotification(version: version)
            }
        case .upToDate:
            clearPersistedAvailableUpdate()
        default:
            break
        }
    }

    private func postUpdateAvailableUserNotification(version: String) {
        let settings = SettingsModel.shared.settings
        guard settings.automaticUpdateChecksEnabled,
              settings.updateAvailableNotificationsEnabled else { return }
        guard !NSApp.isActive else { return }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { notificationSettings in
            guard notificationSettings.authorizationStatus == .authorized
                || notificationSettings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Sapphire \(version) is available"
            content.body = "A new version is ready to download. Open Settings → About → Updates to install it."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "sapphire-update-available-\(version)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        if enabled {
            startPeriodicChecks(interval: periodicCheckInterval)
        } else {
            stopPeriodicChecks()
        }
    }

    private func persistAvailableUpdate(version: String, asset: GitHubReleaseAsset) {
        let persisted = PersistedAvailableUpdate(version: version, asset: asset)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: persistedAvailableUpdateKey)
    }

    private func clearPersistedAvailableUpdate() {
        UserDefaults.standard.removeObject(forKey: persistedAvailableUpdateKey)
    }

    private func restorePersistedAvailableUpdateIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: persistedAvailableUpdateKey),
              let persisted = try? JSONDecoder().decode(PersistedAvailableUpdate.self, from: data) else {
            clearPersistedAvailableUpdate()
            return
        }
        let stillRelevant = SapphireUpdateSource.isCNVersion(persisted.version)
            && AppVersionOrdering.isNewer(persisted.version, than: SapphireUpdateSource.currentReleaseVersion)
        guard stillRelevant,
              Self.isSafeReleaseAssetName(persisted.asset.name),
              persisted.asset.name.lowercased().hasSuffix(".zip"),
              persisted.asset.name.lowercased().contains("sapphire"),
              persisted.asset.size.map({ $0 > 0 && $0 <= Self.maximumDownloadBytes }) == true,
              SapphireUpdateSource.isReleaseAssetURL(persisted.asset.browserDownloadUrl) else {
            clearPersistedAvailableUpdate()
            return
        }
        status = .available(version: persisted.version, asset: persisted.asset)
    }

    func checkForUpdates() {
        beginCheck()
    }

    func checkForBetaUpdates() {
        beginCheck()
    }

    func checkForUpdatesMatchingCurrentChannel() {
        beginCheck()
    }

    private func beginCheck() {
        switch status {
        case .checking, .downloading, .downloaded, .installing:
            return
        default:
            break
        }
        let previousStatus = status
        applyStatus(.checking)
        lastCheckAttemptAt = Date()
        lastCheckError = nil
        lastFailureWasRateLimit = false
        Task { await performCheck(previousStatus: previousStatus) }
    }

    private func performCheck(previousStatus: UpdateStatus) async {
        do {
            let fetched = try await fetchReleasesWithRetry()
            isUsingCachedReleaseData = fetched.usedCache
            // CN 发行目前为公开预发布，与上游付费 Beta 通道无关。
            let releases = fetched.releases.filter {
                !$0.draft && SapphireUpdateSource.isCNVersion($0.marketingVersion)
            }
            guard let release = releases.max(by: {
                AppVersionOrdering.compare($0.marketingVersion, $1.marketingVersion) == .orderedAscending
            }) else {
                throw UpdateMetadataError.noEligibleRelease
            }

            let latestVersion = release.marketingVersion
            let shouldOffer = AppVersionOrdering.isNewer(
                latestVersion, than: SapphireUpdateSource.currentReleaseVersion
            )

            applyReleaseNotes(from: releases, offeredVersion: shouldOffer ? latestVersion : nil)
            if shouldOffer {
                guard let asset = Self.preferredUpdateAsset(in: release) else {
                    throw UpdateMetadataError.noEligibleAsset
                }
                applyStatus(.available(version: latestVersion, asset: asset))
                if SettingsModel.shared.settings.automaticUpdateChecksEnabled,
                   SettingsModel.shared.settings.automaticallyDownloadSapphireUpdates {
                    downloadUpdate(asset: asset, version: latestVersion)
                }
            } else {
                applyStatus(.upToDate)
            }

            if let retryNotBefore = fetched.retryNotBefore {
                scheduleRateLimitRetry(notBefore: retryNotBefore)
            } else if !fetched.usedCache {
                markCheckSuccessful()
            } else {
                scheduleNextCheck(after: 30 * 60)
            }
        } catch {
            isUsingCachedReleaseData = false
            recordCheckFailure(error)
            switch previousStatus {
            case .available, .downloaded:
                applyStatus(previousStatus)
            default:
                applyStatus(.error(error.localizedDescription))
            }
        }
    }

    private func fetchReleasesWithRetry() async throws -> FetchedGitHubReleases {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await fetchReleases()
            } catch {
                lastError = error
                guard attempt < 2, Self.isTransient(error) else { break }
                let delay = UInt64((pow(2.0, Double(attempt)) + Double.random(in: 0...0.35)) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        if let cached = try? cachedReleases(maxAge: 7 * 24 * 60 * 60) {
            let retryNotBefore: Date?
            if let metadataError = lastError as? UpdateMetadataError,
               case .rateLimited(let resetDate) = metadataError {
                retryNotBefore = resetDate
            } else {
                retryNotBefore = nil
            }
            return FetchedGitHubReleases(
                releases: cached,
                usedCache: true,
                retryNotBefore: retryNotBefore
            )
        }
        throw lastError ?? UpdateMetadataError.invalidResponse
    }

    private func fetchReleases(useConditionalRequest: Bool = true) async throws -> FetchedGitHubReleases {
        var request = URLRequest(url: SapphireUpdateSource.metadataURL)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
        if useConditionalRequest,
           let etag = UserDefaults.standard.string(forKey: releasesCacheETagKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 60
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.url?.scheme == "https",
              http.url?.host?.lowercased() == SapphireUpdateSource.metadataURL.host?.lowercased(),
              http.url?.path == SapphireUpdateSource.metadataURL.path else {
            throw UpdateMetadataError.insecureRedirect
        }

        switch http.statusCode {
        case 200:
            guard data.count <= maximumMetadataBytes else { throw UpdateMetadataError.responseTooLarge }
            let releases = try decodeReleases(data)
            UserDefaults.standard.set(data, forKey: releasesCacheKey)
            UserDefaults.standard.set(Date(), forKey: releasesCacheDateKey)
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                UserDefaults.standard.set(etag, forKey: releasesCacheETagKey)
            } else {
                UserDefaults.standard.removeObject(forKey: releasesCacheETagKey)
            }
            return FetchedGitHubReleases(releases: releases, usedCache: false, retryNotBefore: nil)
        case 304:
            guard useConditionalRequest else { throw UpdateMetadataError.invalidResponse }
            do {
                let releases = try cachedReleasesRegardlessOfAge()
                UserDefaults.standard.set(Date(), forKey: releasesCacheDateKey)
                if let etag = http.value(forHTTPHeaderField: "ETag") {
                    UserDefaults.standard.set(etag, forKey: releasesCacheETagKey)
                }
                return FetchedGitHubReleases(releases: releases, usedCache: false, retryNotBefore: nil)
            } catch {
                UserDefaults.standard.removeObject(forKey: releasesCacheKey)
                UserDefaults.standard.removeObject(forKey: releasesCacheDateKey)
                UserDefaults.standard.removeObject(forKey: releasesCacheETagKey)
                return try await fetchReleases(useConditionalRequest: false)
            }
        case 403, 429:
            let resetDate = http.value(forHTTPHeaderField: "X-RateLimit-Reset")
                .flatMap(TimeInterval.init)
                .map(Date.init(timeIntervalSince1970:))
            let retryAfterDate = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
                .map { Date().addingTimeInterval($0) }
            let retryDate = [resetDate, retryAfterDate].compactMap { $0 }.max()
            throw UpdateMetadataError.rateLimited(retryDate)
        default:
            throw UpdateMetadataError.httpStatus(http.statusCode)
        }
    }

    private func decodeReleases(_ data: Data) throws -> [GitHubRelease] {
        do {
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            guard !releases.isEmpty else { throw UpdateMetadataError.invalidMetadata }
            return releases
        } catch let error as UpdateMetadataError {
            throw error
        } catch {
            throw UpdateMetadataError.invalidMetadata
        }
    }

    private func cachedReleases(maxAge: TimeInterval) throws -> [GitHubRelease] {
        guard let date = UserDefaults.standard.object(forKey: releasesCacheDateKey) as? Date else {
            throw UpdateMetadataError.emptyCache
        }
        let age = Date().timeIntervalSince(date)
        guard age >= 0, age <= maxAge else { throw UpdateMetadataError.emptyCache }
        return try cachedReleasesRegardlessOfAge()
    }

    private func cachedReleasesRegardlessOfAge() throws -> [GitHubRelease] {
        guard let data = UserDefaults.standard.data(forKey: releasesCacheKey) else {
            throw UpdateMetadataError.emptyCache
        }
        guard data.count <= maximumMetadataBytes else {
            throw UpdateMetadataError.responseTooLarge
        }
        return try decodeReleases(data)
    }

    nonisolated static func preferredUpdateAsset(in release: GitHubRelease) -> GitHubReleaseAsset? {
        let architecture = machineArchitecture
        let candidates = release.assets.filter { asset in
            let lower = asset.name.lowercased()
            return isSafeReleaseAssetName(asset.name)
                && lower.hasSuffix(".zip")
                && lower.contains("sapphire")
                && SapphireUpdateSource.isReleaseAssetURL(asset.browserDownloadUrl)
                && asset.size.map({ $0 > 0 && $0 <= maximumDownloadBytes }) == true
                && isAssetNameCompatible(asset.name, with: architecture)
        }
        return candidates.sorted { lhs, rhs in
            assetScore(lhs, architecture: architecture) > assetScore(rhs, architecture: architecture)
        }.first
    }

    nonisolated private static var machineArchitecture: String {
        hardwareArchitecture == .arm64 ? "arm64" : "x86_64"
    }

    private enum HardwareArchitecture {
        case arm64
        case x86_64
    }

    nonisolated private static var hardwareArchitecture: HardwareArchitecture {
#if arch(arm64)
        return .arm64
#else
        var translated: Int32 = 0
        var translatedSize = MemoryLayout.size(ofValue: translated)
        if sysctlbyname("sysctl.proc_translated", &translated, &translatedSize, nil, 0) == 0,
           translated == 1 {
            return .arm64
        }

        var arm64Supported: Int32 = 0
        var arm64Size = MemoryLayout.size(ofValue: arm64Supported)
        if sysctlbyname("hw.optional.arm64", &arm64Supported, &arm64Size, nil, 0) == 0,
           arm64Supported == 1 {
            return .arm64
        }
        return .x86_64
#endif
    }

    nonisolated private static func isAssetNameCompatible(_ assetName: String, with architecture: String) -> Bool {
        let name = assetName.lowercased()
        let tokens = name.split { !$0.isLetter && !$0.isNumber }
        if name.contains("universal") { return true }
        let advertisesARM = name.contains("arm64")
            || name.contains("aarch64")
            || name.contains("apple-silicon")
            || name.contains("apple_silicon")
        let advertisesIntel = name.contains("x86_64")
            || name.contains("x86-64")
            || name.contains("amd64")
            || name.contains("intel")
            || tokens.contains("x64")
        guard advertisesARM != advertisesIntel else { return true }
        return architecture == "arm64" ? advertisesARM : advertisesIntel
    }

    nonisolated private static func assetScore(_ asset: GitHubReleaseAsset, architecture: String) -> Int {
        let name = asset.name.lowercased()
        var score = 0
        if name.hasSuffix("-update.zip") { score += 100 }
        if name.contains("universal") { score += 30 }
        if name.contains(architecture) { score += 25 }
        if name == "sapphire.zip" { score += 20 }
        if asset.digest?.lowercased().hasPrefix("sha256:") == true { score += 10 }
        return score
    }

    nonisolated private static func validateRuntimeArchitecture(_ appURL: URL) throws {
        guard let architectures = Bundle(url: appURL)?.executableArchitectures else {
            throw NSError(
                domain: "UpdateError",
                code: 26,
                userInfo: [NSLocalizedDescriptionKey: "The update's executable architecture could not be verified."]
            )
        }
        let required = hardwareArchitecture == .arm64
            ? NSBundleExecutableArchitectureARM64
            : NSBundleExecutableArchitectureX86_64
        guard architectures.contains(where: { $0.intValue == required }) else {
            throw NSError(
                domain: "UpdateError",
                code: 27,
                userInfo: [NSLocalizedDescriptionKey: "This update cannot run natively on this Mac."]
            )
        }
    }

    nonisolated private static func isTrustedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com"
            || host == "objects.githubusercontent.com"
            || host.hasSuffix(".githubusercontent.com")
    }

    nonisolated private static func isSafeReleaseAssetName(_ name: String) -> Bool {
        !name.isEmpty
            && name.utf8.count <= 255
            && name == (name as NSString).lastPathComponent
            && !name.contains("/")
            && !name.contains("\\")
            && !name.contains(":")
            && !name.contains("\0")
            && name != "."
            && name != ".."
    }

    private static func isTransient(_ error: Error) -> Bool {
        if let metadata = error as? UpdateMetadataError {
            switch metadata {
            case .httpStatus(let code): return code == 408 || code == 425 || (500...599).contains(code)
            case .invalidResponse: return true
            case .rateLimited: return false
            default: return false
            }
        }
        if let urlError = error as? URLError {
            return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                    .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable].contains(urlError.code)
        }
        return false
    }

    private func markCheckSuccessful() {
        let now = Date()
        lastSuccessfulCheckAt = now
        lastCheckError = nil
        consecutiveFailures = 0
        UserDefaults.standard.set(now, forKey: lastSuccessfulCheckKey)
        UserDefaults.standard.set(0, forKey: failureCountKey)
        scheduleNextCheck(after: periodicCheckInterval)
    }

    private func recordCheckFailure(_ error: Error) {
        lastCheckError = error.localizedDescription
        if let metadataError = error as? UpdateMetadataError,
           case .rateLimited = metadataError {
            lastFailureWasRateLimit = true
        } else {
            lastFailureWasRateLimit = false
        }
        consecutiveFailures += 1
        UserDefaults.standard.set(consecutiveFailures, forKey: failureCountKey)

        if let metadataError = error as? UpdateMetadataError,
           case .rateLimited(let resetDate) = metadataError,
           let resetDate {
            scheduleRateLimitRetry(notBefore: resetDate)
            return
        }

        let exponent = min(consecutiveFailures - 1, 5)
        let base = min(pow(2.0, Double(exponent)) * 15 * 60, 6 * 60 * 60)
        scheduleNextCheck(after: base + Double.random(in: 0...120))
    }

    private func scheduleRateLimitRetry(notBefore resetDate: Date) {
        let untilReset = max(resetDate.timeIntervalSinceNow, 60)
        scheduleNextCheck(after: untilReset + Double.random(in: 30...180))
    }

    private func scheduleNextCheck(after interval: TimeInterval) {
        let date = Date().addingTimeInterval(max(interval, 60))
        nextScheduledCheckAt = date
        UserDefaults.standard.set(date, forKey: nextScheduledCheckKey)
        scheduleTimerForNextCheck()
    }

    private func applyReleaseNotes(from releases: [GitHubRelease], offeredVersion: String?) {
        let targetVersion = offeredVersion ?? SapphireUpdateSource.currentReleaseVersion
        if let match = Self.findRelease(version: targetVersion, in: releases) {
            releaseNotesVersion = match.marketingVersion
            releaseNotes = Self.normalizedNotes(match.body)
            releaseNotesURL = match.htmlUrl.flatMap { URL(string: $0) }
            return
        }
        releaseNotesVersion = targetVersion
        releaseNotes = nil
        releaseNotesURL = SapphireUpdateSource.releasesURL
    }

    private static func normalizedNotes(_ body: String?) -> String? {
        guard let body = body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else {
            return nil
        }
        return body
    }

    private static func findRelease(version: String, in releases: [GitHubRelease]) -> GitHubRelease? {
        releases.first { release in
            AppVersionOrdering.compare(release.marketingVersion, version) == .orderedSame
                || AppVersionOrdering.compare(
                    release.tagName
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "v", with: "", options: .caseInsensitive),
                    version
                ) == .orderedSame
        }
    }

    func checkInBackgroundIfNeeded(force: Bool = false) {
        guard SettingsModel.shared.settings.automaticUpdateChecksEnabled else { return }
        switch status {
        case .checking, .downloading, .downloaded, .installing:
            return
        default:
            break
        }

        let isDue = nextScheduledCheckAt.map { $0 <= Date() } ?? true
        guard force || isDue else { return }
        checkForUpdatesMatchingCurrentChannel()
    }

    func startPeriodicChecks(interval: TimeInterval) {
        stopPeriodicChecks()

        periodicCheckInterval = interval
        guard SettingsModel.shared.settings.automaticUpdateChecksEnabled else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if SettingsModel.shared.settings.automaticallyDownloadSapphireUpdates,
               case .available(_, let asset) = self.status {
                self.downloadUpdate(asset: asset)
                return
            }
            let overdue = self.nextScheduledCheckAt.map { $0 <= Date() } ?? true
            self.checkInBackgroundIfNeeded(force: overdue)
        }
        initialCheckWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 4...12), execute: work)
        scheduleTimerForNextCheck()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                self?.checkInBackgroundIfNeeded()
            }
        }

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkInBackgroundIfNeeded() }
        }

        let monitor = NWPathMonitor()
        networkMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                guard let self,
                      self.lastCheckError != nil,
                      !self.lastFailureWasRateLimit else { return }
                self.checkInBackgroundIfNeeded(force: true)
            }
        }
        monitor.start(queue: networkMonitorQueue)
    }

    private func scheduleTimerForNextCheck() {
        timer?.invalidate()
        timer = nil
        guard SettingsModel.shared.settings.automaticUpdateChecksEnabled,
              let nextScheduledCheckAt,
              nextScheduledCheckAt > Date() else { return }

        let delay = nextScheduledCheckAt.timeIntervalSinceNow
        let nextTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer = nil
                self?.checkInBackgroundIfNeeded()
            }
        }
        nextTimer.tolerance = min(60, delay * 0.05)
        timer = nextTimer
    }

    func stopPeriodicChecks() {
        initialCheckWorkItem?.cancel()
        initialCheckWorkItem = nil
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        networkMonitor?.cancel()
        networkMonitor = nil
    }

    func downloadUpdate(asset: GitHubReleaseAsset) {
        let version: String
        if case .available(let availableVersion, _) = status {
            version = availableVersion
        } else {
            version = releaseNotesVersion ?? ""
        }
        downloadUpdate(asset: asset, version: version)
    }

    private func downloadUpdate(asset: GitHubReleaseAsset, version: String) {
        guard SapphireUpdateSource.isReleaseAssetURL(asset.browserDownloadUrl),
              Self.isSafeReleaseAssetName(asset.name),
              asset.name.lowercased().hasSuffix(".zip"),
              asset.name.lowercased().contains("sapphire"),
              asset.size.map({ $0 > 0 && $0 <= Self.maximumDownloadBytes }) == true else {
            applyStatus(.error("The release download did not pass Sapphire's security policy."))
            return
        }

        pendingDownloadAsset = asset
        pendingDownloadVersion = version
        downloadPolicyFailure = nil
        downloadGeneration &+= 1
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 30 * 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        downloadSession = session
        var request = URLRequest(url: asset.browserDownloadUrl)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
        downloadTask = session.downloadTask(with: request)
        downloadTask?.resume()

        applyStatus(.downloading(progress: 0.0))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard downloadSession === session else { return }
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let finalURL = response.url,
              Self.isTrustedDownloadURL(finalURL),
              let asset = pendingDownloadAsset else {
            applyStatus(.error("The update download returned an invalid response."))
            return
        }

        let fileManager = FileManager.default
        do {
            let generation = downloadGeneration
            let tempDir = fileManager.temporaryDirectory
                .appendingPathComponent("SapphireUpdate-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let destinationURL = tempDir.appendingPathComponent(asset.name)
            try fileManager.moveItem(at: location, to: destinationURL)
            let maximumDownloadBytes = Self.maximumDownloadBytes
            let version = pendingDownloadVersion
            Task.detached(priority: .utility) {
                do {
                    let values = try destinationURL.resourceValues(forKeys: [.fileSizeKey])
                    let actualSize = Int64(values.fileSize ?? 0)
                    guard actualSize > 0, actualSize <= maximumDownloadBytes else {
                        throw NSError(domain: "UpdateError", code: 10, userInfo: [NSLocalizedDescriptionKey: "The update archive has an invalid size."])
                    }
                    if let expectedSize = asset.size, expectedSize > 0, actualSize != expectedSize {
                        throw NSError(domain: "UpdateError", code: 11, userInfo: [NSLocalizedDescriptionKey: "The update archive was incomplete."])
                    }
                    try Self.verifyDigest(of: destinationURL, expected: asset.digest)
                    try Self.validateArchiveEntries(destinationURL)
                    await MainActor.run {
                        guard self.downloadGeneration == generation,
                              self.pendingDownloadAsset == asset,
                              self.pendingDownloadVersion == version,
                              case .downloading = self.status else {
                            try? FileManager.default.removeItem(at: tempDir)
                            return
                        }
                        self.downloadedAssetPath = destinationURL
                        self.applyStatus(.downloaded(path: destinationURL))
                    }
                } catch {
                    try? FileManager.default.removeItem(at: tempDir)
                    await MainActor.run {
                        guard self.downloadGeneration == generation,
                              self.pendingDownloadAsset == asset,
                              self.pendingDownloadVersion == version else { return }
                        self.applyStatus(.error(error.localizedDescription))
                    }
                }
            }
        } catch {
            applyStatus(.error(error.localizedDescription))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, Self.isTrustedDownloadURL(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    private nonisolated static func verifyDigest(of url: URL, expected: String?) throws {
        guard let expected, !expected.isEmpty else { return }
        let pieces = expected.lowercased().split(separator: ":", maxSplits: 1).map(String.init)
        guard pieces.count == 2, pieces[0] == "sha256", pieces[1].count == 64 else {
            throw NSError(domain: "UpdateError", code: 12, userInfo: [NSLocalizedDescriptionKey: "The release contains an unsupported checksum."])
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_024 * 1_024), !data.isEmpty {
            hasher.update(data: data)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == pieces[1] else {
            throw NSError(domain: "UpdateError", code: 13, userInfo: [NSLocalizedDescriptionKey: "The update checksum did not match the signed release metadata."])
        }
    }

    private func isInstallPathUserWritable() -> Bool {
        let appURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        let parentPath = appURL.deletingLastPathComponent().path
        return FileManager.default.isWritableFile(atPath: parentPath)
    }

    nonisolated private static func validateUpdatePublisher(
        candidate: URL,
        replacing installed: URL
    ) throws {
        let installedIdentity = try validatedUpdateIdentity(at: installed)
        let candidateIdentity = try validatedUpdateIdentity(at: candidate)
        guard installedIdentity.identifier == SapphireUpdateSource.bundleIdentifier,
              candidateIdentity.identifier == installedIdentity.identifier,
              candidateIdentity.team == installedIdentity.team else {
            throw NSError(
                domain: "UpdateError",
                code: 26,
                userInfo: [NSLocalizedDescriptionKey: "The update must be the same app, signed by the same Apple developer team."]
            )
        }
    }

    nonisolated private static func validatedUpdateIdentity(at url: URL) throws -> (identifier: String, team: String) {
        // 公开构建的通用验证器是占位实现，更新入口必须与 Helper 一样做真实系统验签。
        var code: SecStaticCode?
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code,
              SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let securedPlist = info[kSecCodeInfoPList as String] as? [String: Any],
              let identifier = securedPlist["CFBundleIdentifier"] as? String,
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty else {
            throw NSError(domain: "UpdateError", code: 25, userInfo: [
                NSLocalizedDescriptionKey: "The app signature could not be verified. Install a signed Sapphire-CN build manually."
            ])
        }
        return (identifier, team)
    }

    nonisolated private static func validatedCandidateVersion(
        at candidate: URL, replacing installed: URL, expectedReleaseVersion: String
    ) throws -> String {
        let candidateBundle = Bundle(url: candidate)
        let installedBundle = Bundle(url: installed)
        let marketing = candidateBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let currentMarketing = installedBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let release = SapphireUpdateSource.releaseVersion(in: candidateBundle)
        let currentRelease = SapphireUpdateSource.releaseVersion(in: installedBundle) ?? "\(currentMarketing)-cn.0-preview"
        let build = candidateBundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let currentBuild = installedBundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let marketingOrder = SapphireVersionOrdering.compare(marketing, currentMarketing)
        // CN 标签用于发行校验；系统版本和递增 build 保持旧 Helper 的升级契约。
        guard let release,
              AppVersionOrdering.compare(release, expectedReleaseVersion) == .orderedSame,
              AppVersionOrdering.isNewer(release, than: currentRelease),
              !marketing.isEmpty,
              marketingOrder == .orderedDescending
                || (marketingOrder == .orderedSame && AppVersionOrdering.isNewer(build, than: currentBuild)) else {
            throw NSError(domain: "UpdateError", code: 14, userInfo: [
                NSLocalizedDescriptionKey: "The signed app must match the offered CN release and have a newer version or build."
            ])
        }
        return marketing
    }

    nonisolated private static func stageForCurrentUserInstallation(
        candidate: URL,
        replacing currentAppURL: URL,
        expectedVersion: String,
        expectedReleaseVersion: String
    ) throws -> URL {
        let fileManager = FileManager.default
        let stagedURL = currentAppURL.deletingLastPathComponent()
            .appendingPathComponent(".Sapphire-update-\(UUID().uuidString).app", isDirectory: true)

        do {
            try fileManager.copyItem(at: candidate, to: stagedURL)
            try validateUpdatePublisher(candidate: stagedURL, replacing: currentAppURL)

            let stagedVersion = try validatedCandidateVersion(
                at: stagedURL, replacing: currentAppURL, expectedReleaseVersion: expectedReleaseVersion
            )
            guard SapphireVersionOrdering.compare(stagedVersion, expectedVersion) == .orderedSame else {
                throw NSError(
                    domain: "UpdateError",
                    code: 24,
                    userInfo: [NSLocalizedDescriptionKey: "The staged app version changed before installation."]
                )
            }
            return stagedURL
        } catch {
            try? fileManager.removeItem(at: stagedURL)
            throw error
        }
    }

    nonisolated static func atomicallyReplaceAppBundle(
        installedURL: URL,
        stagedURL: URL
    ) throws {
        guard installedURL.deletingLastPathComponent().standardizedFileURL
                == stagedURL.deletingLastPathComponent().standardizedFileURL else {
            throw NSError(
                domain: "UpdateError",
                code: 25,
                userInfo: [NSLocalizedDescriptionKey: "The update was not staged on the installed app's volume."]
            )
        }

        _ = try FileManager.default.replaceItemAt(
            installedURL,
            withItemAt: stagedURL,
            backupItemName: nil,
            options: []
        )
    }

    func installAndRelaunch() {
        installAndRelaunch(strategy: .standard)
    }

    // MARK: - Secure update installation

    nonisolated private static func installViaPrivilegedHelper(
        newAppPath: String,
        currentAppPath: String,
        expectedVersion: String
    ) async -> PrivilegedUpdateInstallOutcome {
        guard let version = await XPCClient.shared.helperProtocolVersion(timeout: 5) else {
            return .failure("The privileged update helper is unavailable. Reinstall or repair Sapphire's helper, then try again.")
        }
        guard version >= SapphireHelperProtocolVersion else {
            return .failure("The privileged update helper is out of date. Reinstall or repair Sapphire's helper, then try again.")
        }

        return await withCheckedContinuation { continuation in
            let gate = UpdateInstallContinuationGate()
            func resumeOnce(_ outcome: PrivilegedUpdateInstallOutcome) {
                guard gate.claim() else { return }
                continuation.resume(returning: outcome)
            }

            guard let helper = XPCClient.shared.helper else {
                resumeOnce(.failure("The privileged update helper could not be contacted. Reinstall or repair Sapphire's helper, then try again."))
                return
            }

            helper.installUpdate(
                newAppPath: newAppPath,
                currentAppPath: currentAppPath,
                expectedVersion: expectedVersion
            ) { success, message in
                if success {
                    resumeOnce(.success)
                } else {
                    resumeOnce(.failure(message ?? "The privileged update helper could not install the update."))
                }
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 90) {
                resumeOnce(.failure(
                    "The privileged update helper did not respond within 90 seconds. Sapphire will not start a second installer while the first result is unknown; reopen Sapphire and verify its version before retrying."
                ))
            }
        }
    }

    enum UpdateInstallStrategy {
        case standard
        case withoutPassword
    }

    func installAndRelaunchCurrentMethod() {
        installAndRelaunch(strategy: .standard)
    }

    func installAndRelaunchWithoutPassword() {
        installAndRelaunch(strategy: .withoutPassword)
    }

    private func installAndRelaunch(strategy: UpdateInstallStrategy) {
        guard let downloadedZipPath = downloadedAssetPath else {
            applyStatus(.error("Downloaded file path not found.")); return
        }
        guard let expectedVersion = pendingDownloadVersion, !expectedVersion.isEmpty else {
            applyStatus(.error("The verified release version is missing. Download the update again.")); return
        }

        applyStatus(.installing)

        Task.detached(priority: .userInitiated) {
            do {
                let fileManager = FileManager.default
                try Self.validateArchiveEntries(downloadedZipPath)
                let tempUnzipDirectory = fileManager.temporaryDirectory
                    .appendingPathComponent("SapphireExtract-\(UUID().uuidString)", isDirectory: true)
                try fileManager.createDirectory(at: tempUnzipDirectory, withIntermediateDirectories: true, attributes: nil)
                defer { try? fileManager.removeItem(at: tempUnzipDirectory) }

                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzipProcess.arguments = ["-x", "-k", downloadedZipPath.path, tempUnzipDirectory.path]
                unzipProcess.standardOutput = FileHandle.nullDevice
                unzipProcess.standardError = FileHandle.nullDevice
                try unzipProcess.run()
                unzipProcess.waitUntilExit()

                if unzipProcess.terminationStatus != 0 {
                    throw NSError(domain: "UpdateError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to unzip the update file."])
                }

                let currentAppURL = Bundle.main.bundleURL
                let currentAppValues = try currentAppURL.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard currentAppValues.isSymbolicLink != true else {
                    throw NSError(
                        domain: "UpdateError",
                        code: 23,
                        userInfo: [NSLocalizedDescriptionKey: "Sapphire is running through an application symlink. Move the real app into Applications before updating."]
                    )
                }
                guard let currentBundleIdentifier = Bundle.main.bundleIdentifier,
                      let newAppURL = Self.findUpdateBundle(
                        in: tempUnzipDirectory,
                        bundleIdentifier: currentBundleIdentifier
                      ) else {
                    throw NSError(domain: "UpdateError", code: 3, userInfo: [NSLocalizedDescriptionKey: "The archive did not contain the expected Sapphire app."])
                }
                try Self.validateRuntimeArchitecture(newAppURL)
                try Self.validateUpdatePublisher(candidate: newAppURL, replacing: currentAppURL)
                let candidateVersion = try Self.validatedCandidateVersion(
                    at: newAppURL, replacing: currentAppURL, expectedReleaseVersion: expectedVersion
                )
                let currentAppPath = Bundle.main.bundlePath
                let userWritable = await MainActor.run { self.isInstallPathUserWritable() }
                var stagedAppURL: URL?
                defer {
                    if let stagedAppURL {
                        try? fileManager.removeItem(at: stagedAppURL)
                    }
                }

                if userWritable {
                    let stagedURL = try Self.stageForCurrentUserInstallation(
                        candidate: newAppURL,
                        replacing: currentAppURL,
                        expectedVersion: candidateVersion,
                        expectedReleaseVersion: expectedVersion
                    )
                    stagedAppURL = stagedURL
                    try Self.atomicallyReplaceAppBundle(
                        installedURL: currentAppURL,
                        stagedURL: stagedURL
                    )
                    stagedAppURL = nil
                } else {
                    switch strategy {
                    case .withoutPassword:
                        throw NSError(
                            domain: "UpdateError",
                            code: 9,
                            userInfo: [NSLocalizedDescriptionKey: "Sapphire isn't in a user-writable location. Install or repair the privileged helper, then use the standard install method."]
                        )
                    case .standard:
                        let outcome = await Self.installViaPrivilegedHelper(
                            newAppPath: newAppURL.path,
                            currentAppPath: currentAppPath,
                            expectedVersion: candidateVersion
                        )
                        if case .failure(let message) = outcome {
                            throw NSError(
                                domain: "UpdateError",
                                code: 20,
                                userInfo: [NSLocalizedDescriptionKey: message]
                            )
                        }
                    }
                }

                try Self.scheduleRelaunch(of: currentAppPath)
                await MainActor.run {
                    NSApp.terminate(nil)
                }

            } catch {
                await MainActor.run {
                    self.applyStatus(.error(error.localizedDescription))
                }
            }
        }
    }

    nonisolated static func validateArchiveEntries(_ archiveURL: URL) throws {
        let listingData = try boundedProcessOutput(
            executablePath: "/usr/bin/unzip",
            arguments: ["-Z1", archiveURL.path],
            maximumBytes: maximumArchiveListingBytes
        )
        guard let listing = String(data: listingData, encoding: .utf8) else {
            throw NSError(domain: "UpdateError", code: 15, userInfo: [NSLocalizedDescriptionKey: "The update archive is invalid."])
        }
        let entries = listing.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !entries.isEmpty, entries.count <= maximumArchiveEntryCount else {
            throw NSError(domain: "UpdateError", code: 16, userInfo: [NSLocalizedDescriptionKey: "The update archive contains an unsafe number of files."])
        }

        let attributesData = try boundedProcessOutput(
            executablePath: "/usr/bin/zipinfo",
            arguments: ["-l", archiveURL.path],
            maximumBytes: maximumArchiveListingBytes
        )
        guard let attributesText = String(data: attributesData, encoding: .utf8) else {
            throw NSError(domain: "UpdateError", code: 15, userInfo: [NSLocalizedDescriptionKey: "The update archive has invalid file metadata."])
        }
        let attributeLines = attributesText.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            guard line.count >= 11,
                  let first = line.first,
                  first == "-" || first == "d" || first == "l" else { return false }
            return line[line.index(line.startIndex, offsetBy: 10)].isWhitespace
        }
        guard attributeLines.count == entries.count else {
            throw NSError(domain: "UpdateError", code: 15, userInfo: [NSLocalizedDescriptionKey: "The update archive contains unsupported file metadata."])
        }

        let totalsData = try boundedProcessOutput(
            executablePath: "/usr/bin/zipinfo",
            arguments: ["-t", archiveURL.path],
            maximumBytes: maximumArchiveTotalsBytes
        )
        guard let totalsText = String(data: totalsData, encoding: .utf8),
              let totals = parseArchiveTotals(totalsText),
              totals.entryCount == entries.count,
              totals.entryCount <= maximumArchiveEntryCount,
              totals.uncompressedBytes > 0,
              totals.uncompressedBytes <= maximumExpandedArchiveBytes,
              totals.compressedBytes > 0 else {
            throw NSError(
                domain: "UpdateError",
                code: 21,
                userInfo: [NSLocalizedDescriptionKey: "The update archive has unsafe or inconsistent size metadata."]
            )
        }
        let compressionRatio = Double(totals.uncompressedBytes) / Double(totals.compressedBytes)
        guard compressionRatio <= maximumArchiveCompressionRatio else {
            throw NSError(
                domain: "UpdateError",
                code: 22,
                userInfo: [NSLocalizedDescriptionKey: "The update archive's expanded size is unexpectedly large."]
            )
        }

        var canonicalPaths = Set<String>()
        for (index, path) in entries.enumerated() {
            guard let components = canonicalArchiveComponents(path),
                  canonicalPaths.insert(
                    components.joined(separator: "/")
                        .precomposedStringWithCanonicalMapping
                        .lowercased()
                  ).inserted else {
                throw NSError(domain: "UpdateError", code: 17, userInfo: [NSLocalizedDescriptionKey: "The update archive contains an unsafe path."])
            }

            if attributeLines[index].first == "l" {
                guard !path.hasPrefix("-"),
                      !path.contains(where: { $0 == "*" || $0 == "?" || $0 == "[" }) else {
                    throw NSError(domain: "UpdateError", code: 17, userInfo: [NSLocalizedDescriptionKey: "The update archive contains an unsupported symbolic-link path."])
                }
                let targetData = try boundedProcessOutput(
                    executablePath: "/usr/bin/unzip",
                    arguments: ["-p", archiveURL.path, path],
                    maximumBytes: 4_096
                )
                guard let target = String(data: targetData, encoding: .utf8),
                      isSafeArchiveSymlinkTarget(target, linkComponents: components) else {
                    throw NSError(domain: "UpdateError", code: 17, userInfo: [NSLocalizedDescriptionKey: "The update archive contains an unsafe symbolic link."])
                }
            }
        }
    }

    nonisolated private static func canonicalArchiveComponents(_ path: String) -> [String]? {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains(":"),
              path.utf8.count <= 4_096,
              !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else {
            return nil
        }

        let rawComponents = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var components: [String] = []
        for (index, component) in rawComponents.enumerated() {
            if component.isEmpty {
                guard index == rawComponents.count - 1, path.hasSuffix("/") else { return nil }
                continue
            }
            guard component != ".", component != ".." else { return nil }
            components.append(component)
        }
        return components.isEmpty ? nil : components
    }

    nonisolated private static func isSafeArchiveSymlinkTarget(
        _ target: String,
        linkComponents: [String]
    ) -> Bool {
        guard !target.isEmpty,
              !target.hasPrefix("/"),
              !target.contains("\\"),
              !target.contains(":"),
              target.utf8.count <= 4_096,
              !target.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else {
            return false
        }

        var resolved = Array(linkComponents.dropLast())
        for component in target.split(separator: "/", omittingEmptySubsequences: false) {
            if component.isEmpty || component == "." { continue }
            if component == ".." {
                guard !resolved.isEmpty else { return false }
                resolved.removeLast()
            } else {
                resolved.append(String(component))
            }
        }
        return true
    }

    nonisolated private static func boundedProcessOutput(
        executablePath: String,
        arguments: [String],
        maximumBytes: Int
    ) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        var data = Data()
        while true {
            let chunk = try output.fileHandleForReading.read(upToCount: 64 * 1_024) ?? Data()
            guard !chunk.isEmpty else { break }
            guard chunk.count <= maximumBytes - data.count else {
                process.terminate()
                process.waitUntilExit()
                throw NSError(
                    domain: "UpdateError",
                    code: 15,
                    userInfo: [NSLocalizedDescriptionKey: "The update archive's directory is unexpectedly large."]
                )
            }
            data.append(chunk)
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "UpdateError",
                code: 15,
                userInfo: [NSLocalizedDescriptionKey: "The update archive is invalid."]
            )
        }
        return data
    }

    nonisolated private static func parseArchiveTotals(_ output: String) -> UpdateArchiveTotals? {
        let pattern = #"(\d+)\s+files?,\s+(\d+)\s+bytes uncompressed,\s+(\d+)\s+bytes compressed:"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: output,
                range: NSRange(output.startIndex..<output.endIndex, in: output)
              ),
              let countRange = Range(match.range(at: 1), in: output),
              let uncompressedRange = Range(match.range(at: 2), in: output),
              let compressedRange = Range(match.range(at: 3), in: output),
              let count = Int(output[countRange]),
              let uncompressedBytes = Int64(output[uncompressedRange]),
              let compressedBytes = Int64(output[compressedRange]) else { return nil }
        return UpdateArchiveTotals(
            entryCount: count,
            uncompressedBytes: uncompressedBytes,
            compressedBytes: compressedBytes
        )
    }

    nonisolated private static func findUpdateBundle(in directory: URL, bundleIdentifier: String) -> URL? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        var matches: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true,
                  Bundle(url: url)?.bundleIdentifier == bundleIdentifier else { continue }
            matches.append(url)
            if matches.count > 1 { return nil }
        }
        return matches.first
    }

    nonisolated private static func scheduleRelaunch(of appPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open -n \"$2\"",
            "sapphire-relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            appPath
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard downloadSession === session else {
            session.finishTasksAndInvalidate()
            return
        }
        defer {
            session.finishTasksAndInvalidate()
            downloadSession = nil
            downloadTask = nil
        }
        if let error {
            if (error as NSError).code == NSURLErrorCancelled {
                if let downloadPolicyFailure {
                    self.downloadPolicyFailure = nil
                    applyStatus(.error(downloadPolicyFailure))
                } else {
                    restoreAvailableDownloadState()
                }
            } else {
                applyStatus(.error("Download failed: \(error.localizedDescription)"))
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard downloadSession === session else { return }
        if totalBytesWritten > Self.maximumDownloadBytes
            || totalBytesExpectedToWrite > Self.maximumDownloadBytes {
            downloadPolicyFailure = "The update archive exceeded Sapphire's maximum allowed size."
            downloadTask.cancel()
            return
        }
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        if case .downloading = status {
            applyStatus(.downloading(progress: progress))
        }
    }

    func cancelDownload() {
        downloadGeneration &+= 1
        downloadPolicyFailure = nil
        downloadTask?.cancel()
        downloadTask = nil
        restoreAvailableDownloadState()
    }

    private func restoreAvailableDownloadState() {
        if let pendingDownloadVersion, let pendingDownloadAsset {
            applyStatus(.available(version: pendingDownloadVersion, asset: pendingDownloadAsset))
        } else {
            applyStatus(.upToDate)
        }
    }
}
