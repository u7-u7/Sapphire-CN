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
struct SystemNotificationRecord {
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
    private var startedAt: TimeInterval
    private var deliveredRecords: [Int64: TimeInterval] = [:]
    private let maximumAge: TimeInterval = 120

    init(now: Date = Date()) { startedAt = now.timeIntervalSinceReferenceDate }

    func cutoff(now: Date) -> TimeInterval {
        max(startedAt, now.timeIntervalSinceReferenceDate - maximumAge)
    }

    mutating func accept(id: Int64, deliveredAt: TimeInterval, now: Date) -> Bool {
        let earliest = cutoff(now: now)
        deliveredRecords = deliveredRecords.filter { $0.value >= earliest }
        guard deliveredAt > 0, deliveredAt >= earliest,
              deliveredAt <= now.timeIntervalSinceReferenceDate + 5,
              deliveredRecords[id] != deliveredAt else { return false }
        deliveredRecords[id] = deliveredAt
        return true
    }
}

/// 保持当前展示项稳定，避免一次数据库写入中的后续通知覆盖队首。
struct NotificationDeliveryQueue<Element: Identifiable> where Element.ID: Hashable {
    private(set) var items: [Element] = []
    private let capacity: Int

    init(capacity: Int = 100) { self.capacity = max(1, capacity) }

    var first: Element? { items.first }

    mutating func enqueue(_ element: Element) {
        guard !items.contains(where: { $0.id == element.id }) else { return }
        // 保留正在阅读的首项；突发洪峰时丢弃最旧的待展示项。
        if items.count == capacity {
            guard capacity > 1 else { return }
            items.remove(at: 1)
        }
        items.append(element)
    }

    mutating func dismiss(id: Element.ID) {
        // 旧视图的延迟回调不能关闭已经切换到的新通知。
        guard first?.id == id else { return }
        items.removeFirst()
    }

    mutating func retain(where predicate: (Element) -> Bool) {
        items.removeAll { !predicate($0) }
    }
}
