//
//  NotificationManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-07
//

import SwiftUI
import Foundation
import Combine
import AppKit
import SQLite
import Contacts
import AVFoundation
import OSLog

struct NotificationPayload: Identifiable, Equatable {
    let id: String
    let presentationID = UUID()
    let appIdentifier: String
    let title: String
    let body: String
    let date: Date
    let appIcon: NSImage?

    var hasAudioAttachment: Bool {
        let lowerBody = body.lowercased()
        return lowerBody.contains("audio message") || lowerBody.contains("sent an audio message") || lowerBody.contains("audio file")
    }
    var hasImageAttachment: Bool {
        let lowerBody = body.lowercased()
        return lowerBody.contains("sent an image") || lowerBody.contains("image file")
    }

    var verificationCode: String? {
        VerificationCodeDetector.find(in: "\(title) \(body)")
    }

    var appName: String {
        switch appIdentifier {
        case "com.apple.iChat", "com.apple.MobileSMS": return "Messages"
        case "com.apple.facetime": return "FaceTime"
        case "com.apple.sharingd": return "AirDrop"
        default:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appIdentifier) {
                return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            }
            return appIdentifier.split(separator: ".").last.map(String.init) ?? "Notification"
        }
    }

    static func == (lhs: NotificationPayload, rhs: NotificationPayload) -> Bool {
        lhs.id == rhs.id && lhs.presentationID == rhs.presentationID
    }
}

struct MessageAttachment {
    enum AttachmentType { case image, audio, other }
    let localURL: URL
    let originalMimeType: String
    var type: AttachmentType {
        if originalMimeType.starts(with: "image/") { return .image }
        if originalMimeType.starts(with: "audio/") { return .audio }
        let pathExtension = localURL.pathExtension.lowercased()
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "heic", "tiff"]
        let audioExtensions = ["m4a", "mp3", "caf", "wav", "aiff"]
        if imageExtensions.contains(pathExtension) { return .image }
        if audioExtensions.contains(pathExtension) { return .audio }
        return .other
    }
}

enum TapbackType: String, CaseIterable {
    case love, like, dislike, laugh, emphasize, question
    var systemImage: String {
        switch self {
        case .love: return "heart.fill"; case .like: return "hand.thumbsup.fill"; case .dislike: return "hand.thumbsdown.fill"; case .laugh: return "face.smiling.inverse"; case .emphasize: return "exclamationmark.2"; case .question: return "questionmark"
        }
    }
}

class iMessageActionManager {
    static let shared = iMessageActionManager()
    private var audioPlayer: AVPlayer?
    private var chatDbConnection: Connection?
    private init() { setupChatDatabaseConnection() }
    private func setupChatDatabaseConnection() {
        let chatDbPath = ("~/Library/Messages/chat.db" as NSString).expandingTildeInPath
        do { chatDbConnection = try Connection(chatDbPath, readonly: true) } catch { print("iMessageActionManager: ERROR: Could not connect to chat.db: \(error)") }
    }
    func sendMessage(_ message: String, to recipientName: String) {
        Task(priority: .userInitiated) {
            let contactIdentifiers = await _getContactIdentifiers(forName: recipientName)
            guard !contactIdentifiers.isEmpty else { return }
            let identifiersString = contactIdentifiers.map { "\"\($0)\"" }.joined(separator: ", ")
            let sanitizedMessage = message.replacingOccurrences(of: "\"", with: "\\\"")
            let scriptTemplate = """
            tell application "Messages"
                set identifierList to {%@}
                set messageSent to false
                repeat with anIdentifier in identifierList
                    if not messageSent then
                        try
                            send "%@" to participant anIdentifier
                            set messageSent to true
                            exit repeat
                        on error
                        end try
                    end if
                end repeat
            end tell
            """
            let finalScript = String(format: scriptTemplate, identifiersString, sanitizedMessage)
            _runAppleScript(finalScript)
        }
    }
    func sendTapback(type tapbackType: TapbackType, to recipientName: String) {
        Task(priority: .userInitiated) {
            let contactIdentifiers = await _getContactIdentifiers(forName: recipientName)
            guard let primaryIdentifier = contactIdentifiers.first else { return }
            let sanitizedIdentifier = primaryIdentifier.replacingOccurrences(of: "\"", with: "\\\"")
            let tapbackValue = tapbackType.rawValue
            let script = """
            tell application "Messages"
                try
                    set targetChat to 1st chat whose participants's handle contains "\(sanitizedIdentifier)"
                    set lastMessage to last message of targetChat
                    tapback "\(tapbackValue)" to lastMessage
                on error errMsg
                end try
            end tell
            """
            _runAppleScript(script)
        }
    }
    func fetchContactImage(forName name: String) async -> NSImage? {
        let store = CNContactStore()
        let keysToFetch = [CNContactImageDataKey] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: name)
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return nil }
        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            if let contact = contacts.first, let imageData = contact.imageData { return NSImage(data: imageData) }
        } catch { print("iMessageActionManager: Failed to fetch contact image for \(name): \(error)") }
        return nil
    }
    func replyToLastMessage() { if !NSWorkspace.shared.launchApplication("Messages") { print("iMessageActionManager: Could not launch Messages.app") } }
    func markConversationAsRead(senderName: String) {
        let sanitizedSenderName = senderName.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Messages"
            try
                set targetChat to first chat whose name is "\(sanitizedSenderName)"
                mark targetChat as read
            on error
            end try
        end tell
        """
        _runAppleScript(script)
    }
    func fetchAndCopyLatestAttachment(for senderName: String) async -> MessageAttachment? {
        guard let db = chatDbConnection else { return nil }
        do {
            let chat = Table("chat"), msg = Table("message"), att = Table("attachment"), c_m_j = Table("chat_message_join"), m_a_j = Table("message_attachment_join")
            let cId = Expression<Int64>("ROWID"), mId = Expression<Int64>("ROWID"), aId = Expression<Int64>("ROWID"), dName = Expression<String?>("display_name"), date = Expression<Int64>("date"), fName = Expression<String?>("filename"), mType = Expression<String?>("mime_type")
            let query = chat.join(c_m_j, on: chat[cId] == c_m_j[Expression<Int64>("chat_id")]).join(msg, on: c_m_j[Expression<Int64>("message_id")] == msg[mId]).join(m_a_j, on: msg[mId] == m_a_j[Expression<Int64>("message_id")]).join(att, on: m_a_j[Expression<Int64>("attachment_id")] == att[aId]).filter(dName == senderName && fName != nil && mType != nil).order(date.desc).limit(1).select(fName, mType)
            if let row = try db.pluck(query), let path = row[fName], let mimeType = row[mType] {
                let fullPath = (path as NSString).expandingTildeInPath, originalURL = URL(fileURLWithPath: fullPath), tempDir = FileManager.default.temporaryDirectory, tempURL = tempDir.appendingPathComponent(originalURL.lastPathComponent)
                if FileManager.default.fileExists(atPath: tempURL.path) { try? FileManager.default.removeItem(at: tempURL) }
                try FileManager.default.copyItem(at: originalURL, to: tempURL)
                return MessageAttachment(localURL: tempURL, originalMimeType: mimeType)
            }
        } catch { print("iMessageActionManager: ERROR: Database query for attachment failed: \(error).") }
        return nil
    }
    func playAudio(at url: URL) { self.audioPlayer = AVPlayer(url: url); self.audioPlayer?.play() }
    private func _getContactIdentifiers(forName name: String) async -> [String] {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        var isAuthorized = false
        switch status { case .authorized: isAuthorized = true; case .denied, .restricted: return []; case .notDetermined: do { isAuthorized = try await store.requestAccess(for: .contacts) } catch { return [] }; @unknown default: return [] }
        guard isAuthorized else { return [] }
        var identifiers: [String] = []
        let keysToFetch = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: name)
        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            guard let contact = contacts.first else { return [] }
            contact.phoneNumbers.forEach { identifiers.append($0.value.stringValue.filter("0123456789+".contains)) }
            contact.emailAddresses.forEach { identifiers.append(String($0.value)) }
            return identifiers.filter { !$0.isEmpty }
        } catch { return [] }
    }
    private func _runAppleScript(_ script: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            AppleScriptRunner.execute(script, error: &error)
            if let err = error { print("iMessageActionManager: AppleScript Error: \(err)") }
        }
    }
}

enum NotificationMonitoringStatus: Equatable {
    case stopped, connecting, monitoring, databaseUnavailable, accessRequired, failed

    var message: String {
        switch self {
        case .stopped: return "Notification mirroring is off."
        case .connecting: return "Connecting to system notifications…"
        case .monitoring: return "Listening for new notifications from all enabled apps."
        case .databaseUnavailable: return "The system notification database is not available on this macOS version."
        case .accessRequired: return "Allow Full Disk Access for Sapphire, then retry. A restart may be required."
        case .failed: return "Cannot read system notifications. Retry or check macOS compatibility."
        }
    }
}

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var latestNotification: NotificationPayload?
    @Published private(set) var monitoringStatus: NotificationMonitoringStatus = .stopped
    @Published private(set) var realtimeStatus: NotificationRealtimeStatus = .disabled
    private let frequency: TimeInterval
    private var dbPath: String?
    private var databaseFileNumber: UInt64?
    private var dbConnection: Connection?
    private var fileWatchers: [String: (inode: UInt64, source: DispatchSourceFileSystemObject)] = [:]
    private var pendingWALCheck: DispatchWorkItem?
    private var pollTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var deliveryQueue = NotificationDeliveryQueue<NotificationPayload>(groupingBy: { $0.appIdentifier.lowercased() })
    private var deliveryCursor = NotificationDeliveryCursor()
    private let settingsModel = SettingsModel.shared
    private var isStarted = false
    private var editingPresentationID: UUID?
    private var nextConnectionAttemptAt = Date.distantPast
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "NotificationDelivery")
    private let realtimeService = NotificationRealtimeService()
    private var ingressDeduplicator = NotificationIngressDeduplicator()
    private var desiredRealtime = false
    private var realtimeConfiguration: Task<Void, Never>?

    var hasPendingNotifications: Bool { deliveryQueue.items.count > 1 }
    var isEditingNotification: Bool { editingPresentationID != nil }

    init(frequency: TimeInterval = 1.0, silent: Bool = true) {
        self.frequency = max(1, frequency)
        realtimeService.shouldManageApplication = { [weak self] source in self?.isApplicationEnabled(source) == true }
        realtimeService.onMessages = { [weak self] messages, observedAt in
            self?.receiveRealtime(messages, observedAt: observedAt)
        }
        realtimeService.onNativeRestored = { [weak self] in
            guard let self else { return }
            // 原生复位后清除了岛上展示，再次接管同一条消息时必须重新提供展示，不能被旧去重记录吞掉。
            self.ingressDeduplicator = NotificationIngressDeduplicator()
            let editing = self.editingPresentationID
            self.deliveryQueue.retain { $0.presentationID == editing }
            self.publishQueueHead()
        }
        realtimeService.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.realtimeStatus = $0 }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshConnection(forceReconnect: true) }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.publishQueueHead() }
            .store(in: &cancellables)
        settingsModel.$settings
            .removeDuplicates { old, new in
                old.masterNotificationsEnabled == new.masterNotificationsEnabled
                    && old.notificationRealtimeEnabled == new.notificationRealtimeEnabled
                    && old.onlyShowVerificationCodeNotifications == new.onlyShowVerificationCodeNotifications
                    && old.systemNotificationsEnabled == new.systemNotificationsEnabled
                    && old.appNotificationStates == new.appNotificationStates
                    && old.iMessageNotificationsEnabled == new.iMessageNotificationsEnabled
                    && old.airDropNotificationsEnabled == new.airDropNotificationsEnabled
                    && old.faceTimeNotificationsEnabled == new.faceTimeNotificationsEnabled
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyNotificationSettings() }
            .store(in: &cancellables)
    }

    deinit {
        for watcher in fileWatchers.values { watcher.source.cancel() }
        pendingWALCheck?.cancel()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        refreshConnection()
        configureRealtime()
        // 文件监听保证及时性；低频检查补偿 WAL 重建、授权变化和漏事件。
        pollTimer = Timer.publish(every: frequency, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refreshConnection() }
    }

    func retryConnection() {
        disconnect()
        start()
        refreshConnection(forceReconnect: true)
        configureRealtime(forceRestart: true)
    }

    private func applyNotificationSettings() {
        guard isStarted else { return }
        deliveryQueue.retain { self.shouldShowNotification($0) }
        publishQueueHead()
        refreshConnection(forceReconnect: true)
        configureRealtime()
    }

    private func configureRealtime(forceRestart: Bool = false) {
        let desired = settingsModel.settings.masterNotificationsEnabled && settingsModel.settings.notificationRealtimeEnabled
        guard desired != desiredRealtime || forceRestart else { return }
        desiredRealtime = desired
        realtimeService.suspend()
        let previous = realtimeConfiguration
        realtimeConfiguration = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.desiredRealtime == desired else { return }
            await self.realtimeService.stop()
            if desired, self.desiredRealtime { await self.realtimeService.start() }
        }
    }

    func shutdownRealtime() async {
        desiredRealtime = false
        realtimeService.suspend()
        await realtimeConfiguration?.value
        await realtimeService.stop()
    }

    func recoverStaleNotificationWindows() { realtimeService.recoverStaleWindows() }

    private func receiveRealtime(_ messages: [NotificationRealtimeMessage], observedAt: Date) {
        guard desiredRealtime else { return }
        for message in messages {
            let event = NotificationIngressEvent(channel: .native, appIdentifier: message.appIdentifier,
                                                  title: message.title, body: message.body,
                                                  identifier: message.nativeIdentifier, observedAt: observedAt)
            guard ingressDeduplicator.shouldAccept(event, now: observedAt) else { continue }
            let payload = NotificationPayload(id: "native-\(message.nativeIdentifier ?? UUID().uuidString)",
                                               appIdentifier: message.appIdentifier, title: message.title, body: message.body,
                                               date: observedAt, appIcon: getAppIcon(for: message.appIdentifier))
            if shouldShowNotification(payload) { deliveryQueue.enqueue(payload, replacingCurrent: !isEditingNotification) }
        }
        publishQueueHead()
    }

    private func refreshConnection(forceReconnect: Bool = false) {
        guard isStarted else { return }
        guard settingsModel.settings.masterNotificationsEnabled else {
            disconnect()
            setMonitoringStatus(.stopped)
            return
        }
        if let dbPath {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: dbPath)
                if (attributes[.systemFileNumber] as? NSNumber)?.uint64Value != databaseFileNumber { disconnect() }
            } catch { handleDatabaseError(error) }
        }
        if dbConnection == nil {
            // 未授权或不兼容时退避重试，1 秒补偿只针对健康连接，不反复触发系统鉴权。
            guard forceReconnect || Date() >= nextConnectionAttemptAt else { return }
            nextConnectionAttemptAt = Date().addingTimeInterval(5)
            setupDatabaseConnection()
        }
        if dbConnection != nil {
            check()
            watchDatabaseFiles()
        }
    }

    private func disconnect() {
        for watcher in fileWatchers.values { watcher.source.cancel() }
        fileWatchers.removeAll()
        pendingWALCheck?.cancel()
        pendingWALCheck = nil
        dbConnection = nil
        dbPath = nil
        databaseFileNumber = nil
    }

    private func watchDatabaseFiles() {
        guard let dbPath else { return }
        let paths = [dbPath, dbPath + "-wal", (dbPath as NSString).deletingLastPathComponent]
        for path in paths {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else {
                fileWatchers.removeValue(forKey: path)?.source.cancel()
                continue
            }
            guard fileWatchers[path]?.inode != inode else { continue }
            // 保留健康监听，避免每条通知都销毁并重建 WAL 监听时漏掉紧随的写入。
            fileWatchers.removeValue(forKey: path)?.source.cancel()
            if let source = watch(path: path) { fileWatchers[path] = (inode, source) }
        }
    }

    private func watch(path: String) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .revoke], queue: .main
        )
        source.setEventHandler { [weak self] in self?.scheduleCheck() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func scheduleCheck() {
        guard pendingWALCheck == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingWALCheck = nil
            self.refreshConnection()
        }
        pendingWALCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    func dismissNotification(id: UUID) {
        deliveryQueue.dismiss(where: { $0.presentationID == id })
        publishQueueHead()
    }

    func setNotificationEditing(_ isEditing: Bool, id: UUID) {
        if isEditing {
            guard latestNotification?.presentationID == id else { return }
            editingPresentationID = id
        } else if editingPresentationID == id {
            editingPresentationID = nil
            deliveryQueue.coalesceCurrentGroup()
            publishQueueHead()
        }
    }

    private func publishQueueHead() {
        // 队列等候过久时不补播陈旧提醒，正在展示的通知由活动计时器关闭。
        let currentID = latestNotification?.id
        deliveryQueue.retain {
            self.shouldShowNotification($0) && ($0.id == currentID || Date().timeIntervalSince($0.date) < 120)
        }
        if editingPresentationID != deliveryQueue.first?.presentationID { editingPresentationID = nil }
        if latestNotification != deliveryQueue.first {
            latestNotification = deliveryQueue.first
            #if DEBUG
            if let notification = latestNotification {
                let age = Date().timeIntervalSince(notification.date)
                // 仅记录延迟和队列长度，不写出来源、标题、正文或验证码。
                logger.debug("Notification prepared: deliveryAge=\(age, privacy: .public)s queuedItems=\(self.deliveryQueue.items.count, privacy: .public)")
            }
            #endif
        }
    }

    private func databaseCandidates() -> [String] {
        let home = NSHomeDirectory()
        var paths = ["\(home)/Library/Group Containers/group.com.apple.usernoted/db2/db"]
        if FileManager.default.fileExists(atPath: paths[0]) { return paths }
        guard let result = ProcessRunner.runSync(executablePath: "/usr/bin/getconf", arguments: ["DARWIN_USER_DIR"], timeout: 10),
              !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return paths
        }
        let directory = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        paths += ["\(directory)com.apple.NotificationCenter/db2/db", "\(directory)com.apple.notificationcenter/db2/db"]
        return paths
    }

    private func setupDatabaseConnection() {
        setMonitoringStatus(.connecting)
        do {
            guard let path = databaseCandidates().first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                setMonitoringStatus(.databaseUnavailable)
                return
            }
            let connection = try Connection(path, readonly: true)
            // 初次连接和权限恢复时只展示之后的新消息，避免把历史通知重新弹出来。
            let record = Table("record"), recId = Expression<Int64>("rec_id")
            _ = try connection.pluck(record.select(recId, Expression<Double?>("delivered_date"), Expression<Data>("data")).limit(1))
            deliveryCursor = NotificationDeliveryCursor()
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            databaseFileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
            dbPath = path
            dbConnection = connection
            setMonitoringStatus(.monitoring)
            watchDatabaseFiles()
        } catch { handleDatabaseError(error) }
    }

    private func setMonitoringStatus(_ status: NotificationMonitoringStatus) {
        guard monitoringStatus != status else { return }
        monitoringStatus = status
    }

    private func handleDatabaseError(_ error: Error) {
        disconnect()
        let description = String(describing: error).lowercased()
        let accessDenied = ["authorization", "not authorized", "permission", "unable to open"].contains { description.contains($0) }
        setMonitoringStatus(accessDenied ? .accessRequired : .failed)
        // 不记录通知正文或数据库行，避免把私人消息写入诊断日志。
        print("[NotificationManager] Database unavailable (accessRequired=\(accessDenied)): \(error)")
    }

    private func check() {
        guard let db = dbConnection else { return }
        do {
            let record = Table("record"), recId = Expression<Int64>("rec_id")
            let deliveredDate = Expression<Double?>("delivered_date"), data = Expression<Data>("data")
            let now = Date()
            // 重查最近投递窗口，兼容先插入、后更新 delivered_date 的系统通知。
            let query = record.select(recId, data, deliveredDate)
                .where(deliveredDate >= deliveryCursor.cutoff(now: now))
                .order(deliveredDate.asc, recId.asc)
            for row in try db.prepare(query) {
                let rowID = row[recId]
                guard let delivered = row[deliveredDate],
                      let record = try? SystemNotificationRecord.decode(row[data]),
                      deliveryCursor.accept(id: rowID, deliveredAt: delivered, now: now, content: record) else { continue }
                let payload = NotificationPayload(
                    id: String(rowID), appIdentifier: record.appIdentifier, title: record.title, body: record.body,
                    date: Date(timeIntervalSinceReferenceDate: delivered), appIcon: getAppIcon(for: record.appIdentifier)
                )
                // 实时模式只推进DB游标；未展示的DB记录不能占用去重配额，否则会吞掉稍后接管的横幅。
                guard !settingsModel.settings.notificationRealtimeEnabled else { continue }
                let event = NotificationIngressEvent(channel: .database, appIdentifier: record.appIdentifier,
                                                      title: record.title, body: record.body, identifier: String(rowID),
                                                      deliveredAt: payload.date, observedAt: now)
                let isNew = ingressDeduplicator.shouldAccept(event, now: now)
                // 实时模式故障回退原生；不从DB补弹被系统共享/专注策略静音的消息。
                if isNew, shouldShowNotification(payload) {
                    deliveryQueue.enqueue(payload, replacingCurrent: !isEditingNotification)
                }
            }
            publishQueueHead()
            setMonitoringStatus(.monitoring)
        } catch { handleDatabaseError(error) }
    }

    private func shouldShowNotification(_ payload: NotificationPayload) -> Bool {
        guard isApplicationEnabled(payload.appIdentifier) else { return false }
        // 使用实时前台应用；ActiveAppMonitor 会忽略 Sapphire 自身，可能保留上一个应用。
        let activeApp = NSWorkspace.shared.frontmostApplication
        guard !NotificationForegroundPolicy.isSourceAppActive(
            sourceIdentifier: payload.appIdentifier, activeIdentifier: activeApp?.bundleIdentifier,
            sourceURL: NSWorkspace.shared.urlForApplication(withBundleIdentifier: payload.appIdentifier),
            activeURL: activeApp?.bundleURL
        ) else { return false }
        return !settingsModel.settings.onlyShowVerificationCodeNotifications || payload.verificationCode != nil
    }

    private func isApplicationEnabled(_ identifier: String) -> Bool {
        let settings = settingsModel.settings
        guard settings.masterNotificationsEnabled else { return false }
        let enabled: Bool
        switch identifier {
        case "com.apple.MobileSMS", "com.apple.iChat": enabled = settings.iMessageNotificationsEnabled
        case "com.apple.sharingd": enabled = settings.airDropNotificationsEnabled
        case "com.apple.facetime": enabled = settings.faceTimeNotificationsEnabled
        default:
            enabled = settings.appNotificationStates[identifier]
                ?? (!identifier.hasPrefix("com.apple.") || settings.systemNotificationsEnabled)
        }
        return enabled
    }

    private func getAppIcon(for identifier: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
