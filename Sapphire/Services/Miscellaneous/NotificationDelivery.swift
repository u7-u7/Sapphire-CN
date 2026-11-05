import Foundation

enum NotificationForegroundPolicy {
    static func isSourceAppActive(
        sourceIdentifier: String, activeIdentifier: String?, sourceURL: URL? = nil, activeURL: URL? = nil
    ) -> Bool {
        guard let activeIdentifier else { return false }
        if sourceIdentifier.caseInsensitiveCompare(activeIdentifier) == .orderedSame { return true }
        guard let sourceURL, let activeURL else { return false }
        let sourcePath = sourceURL.standardizedFileURL.path
        let activePath = activeURL.standardizedFileURL.path
        return sourcePath == activePath || sourcePath.hasPrefix(activePath + "/")
    }
}

/// macOS 通知记录的兼容边界。仅解析通知正文，不访问源应用的聊天数据。
struct SystemNotificationRecord: Equatable {
    let appIdentifier: String
    let title: String
    let body: String

    static func decode(_ data: Data) throws -> SystemNotificationRecord? {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let app = plist["app"] as? String, !app.isEmpty,
              let request = plist["req"] as? [String: Any] else { return nil }
        let title = request["titl"] as? String ?? ""
        let subtitle = request["subt"] as? String ?? ""
        let body = request["body"] as? String ?? ""
        let combinedBody = [subtitle, body].filter { !$0.isEmpty }.joined(separator: "\n")
        guard !title.isEmpty || !combinedBody.isEmpty else { return nil }
        return SystemNotificationRecord(appIdentifier: app, title: title, body: combinedBody)
    }
}

/// 投递时间可以在插入数据库后才补齐，不能只靠 rec_id 跳过已扫描的行。
struct NotificationDeliveryCursor {
    private struct Revision: Equatable {
        let deliveredAt: TimeInterval
        let content: SystemNotificationRecord?
    }
    private var startedAt: TimeInterval
    private var deliveredRecords: [Int64: Revision] = [:]
    private let maximumAge: TimeInterval = 120

    init(now: Date = Date()) { startedAt = now.timeIntervalSinceReferenceDate }

    func cutoff(now: Date) -> TimeInterval {
        max(startedAt, now.timeIntervalSinceReferenceDate - maximumAge)
    }

    mutating func accept(id: Int64, deliveredAt: TimeInterval, now: Date, content: SystemNotificationRecord? = nil) -> Bool {
        let earliest = cutoff(now: now)
        deliveredRecords = deliveredRecords.filter { $0.value.deliveredAt >= earliest }
        let revision = Revision(deliveredAt: deliveredAt, content: content)
        guard deliveredAt > 0, deliveredAt >= earliest,
              deliveredAt <= now.timeIntervalSinceReferenceDate + 5,
              deliveredRecords[id] != revision else { return false }
        deliveredRecords[id] = revision
        return true
    }
}

/// 同应用合并到最新消息，不同应用保留原来的排队顺序。
struct NotificationDeliveryQueue<Element: Identifiable & Equatable> where Element.ID: Hashable {
    private(set) var items: [Element] = []
    private let capacity: Int
    private let groupingKey: ((Element) -> String)?

    init(capacity: Int = 100, groupingBy: ((Element) -> String)? = nil) {
        self.capacity = max(1, capacity)
        self.groupingKey = groupingBy
    }

    var first: Element? { items.first }

    mutating func enqueue(_ element: Element, replacingCurrent: Bool = true) {
        let replacement = items.indices.first { index in
            guard replacingCurrent || index != 0 else { return false }
            if let groupingKey { return groupingKey(items[index]) == groupingKey(element) }
            return items[index].id == element.id
        }
        if let replacement {
            guard items[replacement] != element else { return }
            items[replacement] = element
            return
        }
        guard first != element else { return }
        // 保留正在阅读的首项；突发洪峰时丢弃最旧的待展示项。
        if items.count == capacity {
            guard capacity > 1 else { return }
            items.remove(at: 1)
        }
        items.append(element)
    }

    mutating func coalesceCurrentGroup() {
        guard let groupingKey, let first,
              let next = items.dropFirst().last(where: { groupingKey($0) == groupingKey(first) }) else { return }
        items.removeAll { groupingKey($0) == groupingKey(first) }
        items.insert(next, at: 0)
    }

    mutating func dismiss(id: Element.ID) {
        dismiss(where: { $0.id == id })
    }

    mutating func dismiss(where matches: (Element) -> Bool) {
        // 旧视图的延迟回调必须匹配展示版本，不能关闭同记录的新正文。
        guard let first, matches(first) else { return }
        items.removeFirst()
    }

    mutating func retain(where predicate: (Element) -> Bool) {
        items.removeAll { !predicate($0) }
    }
}

enum NotificationPresentationPolicy {
    static let displayDuration: TimeInterval = 6
    static let maximumContinuousDuration: TimeInterval = 12

    static func duration(startedAt: Date, now: Date, hasPendingApps: Bool) -> TimeInterval {
        guard hasPendingApps else { return displayDuration }
        // 同应用连续刷新时也为其他应用留出展示机会，避免无限延长计时器。
        return max(0.1, min(displayDuration, maximumContinuousDuration - now.timeIntervalSince(startedAt)))
    }
}
