// Run with NotificationDelivery.swift; uses synthetic records, never personal notifications.
import Foundation

@main
struct VerifyNotificationDelivery {
    struct Event: Identifiable { let id: Int }

    static func main() throws {
        precondition(NotificationForegroundPolicy.isSourceAppActive(sourceIdentifier: "com.tencent.xinWeChat", activeIdentifier: "com.tencent.xinWeChat"))
        precondition(NotificationForegroundPolicy.isSourceAppActive(sourceIdentifier: "com.tencent.xinWeChat", activeIdentifier: "com.tencent.xinwechat"))
        precondition(!NotificationForegroundPolicy.isSourceAppActive(sourceIdentifier: "com.tencent.xinWeChat", activeIdentifier: "com.bytedance.macos.feishu"))
        precondition(!NotificationForegroundPolicy.isSourceAppActive(sourceIdentifier: "com.tencent.xinWeChat", activeIdentifier: nil))
        let appURL = URL(fileURLWithPath: "/Applications/Example.app")
        precondition(NotificationForegroundPolicy.isSourceAppActive(sourceIdentifier: "org.example.helper", activeIdentifier: "org.example", sourceURL: appURL.appendingPathComponent("Contents/Helpers/Sender.app"), activeURL: appURL))
        precondition(NotificationForegroundPolicy.isSourceAppActive(sourceIdentifier: "org.example.helper", activeIdentifier: "org.example", sourceURL: appURL, activeURL: appURL))
        precondition(!NotificationForegroundPolicy.isSourceAppActive(sourceIdentifier: "org.example.other", activeIdentifier: "org.example", sourceURL: URL(fileURLWithPath: "/Applications/Example.app-other"), activeURL: appURL))
        var foregroundQueue = NotificationDeliveryQueue<Event>()
        foregroundQueue.enqueue(Event(id: 1))
        foregroundQueue.enqueue(Event(id: 2))
        // 切到来源应用时消费它的已排队通知；离开应用后不能重新回放。
        foregroundQueue.retain { $0.id != 1 }
        precondition(foregroundQueue.first?.id == 2)
        foregroundQueue.dismiss(id: 1)
        precondition(foregroundQueue.first?.id == 2)
        for app in ["com.bytedance.Lark", "com.tencent.xinWeChat", "org.example.any-app"] {
            let data = try PropertyListSerialization.data(
                fromPropertyList: ["app": app, "req": ["titl": "标题", "subt": "副标题", "body": "正文"]],
                format: .binary, options: 0
            )
            let parsed = try SystemNotificationRecord.decode(data)
            precondition(parsed?.appIdentifier == app)
            precondition(parsed?.title == "标题" && parsed?.body == "副标题\n正文")
        }
        let empty = try PropertyListSerialization.data(
            fromPropertyList: ["app": "test", "req": [:]], format: .binary, options: 0
        )
        let emptyRecord = try SystemNotificationRecord.decode(empty)
        precondition(emptyRecord == nil)
        let subtitle = try PropertyListSerialization.data(
            fromPropertyList: ["app": "test", "req": ["subt": "仅副标题"]], format: .xml, options: 0
        )
        let subtitleRecord = try SystemNotificationRecord.decode(subtitle)
        precondition(subtitleRecord?.body == "仅副标题")
        do {
            _ = try SystemNotificationRecord.decode(Data([0, 1, 2]))
            preconditionFailure("Malformed plist must throw")
        } catch { }

        var queue = NotificationDeliveryQueue<Event>(capacity: 3)
        for id in [1, 2, 2, 3] { queue.enqueue(Event(id: id)) }
        precondition(queue.items.map(\.id) == [1, 2, 3], "FIFO and duplicate suppression")
        queue.dismiss(id: 2)
        precondition(queue.first?.id == 1, "A delayed callback must only dismiss its own view")
        queue.dismiss(id: 1)
        precondition(queue.first?.id == 2)
        queue.dismiss(id: 1)
        precondition(queue.first?.id == 2)
        queue.enqueue(Event(id: 4))
        queue.enqueue(Event(id: 5))
        precondition(queue.items.map(\.id) == [2, 4, 5], "Overflow preserves current notification")
        queue.retain { $0.id != 4 }
        precondition(queue.items.map(\.id) == [2, 5])
        queue.retain { _ in false }
        precondition(queue.first == nil)
        var single = NotificationDeliveryQueue<Event>(capacity: 0)
        single.enqueue(Event(id: 1))
        single.enqueue(Event(id: 2))
        precondition(single.first?.id == 1)

        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var cursor = NotificationDeliveryCursor(now: start)
        let now = start.addingTimeInterval(10)
        precondition(!cursor.accept(id: 1, deliveredAt: 999, now: now), "No historical replay")
        precondition(!cursor.accept(id: 2, deliveredAt: 0, now: now), "No undelivered notification")
        precondition(cursor.accept(id: 2, deliveredAt: 1_005, now: now), "A pending row can be delivered later")
        precondition(!cursor.accept(id: 2, deliveredAt: 1_005, now: now), "File event and polling must deduplicate")
        precondition(cursor.accept(id: 1, deliveredAt: 1_006, now: now), "Out-of-order record IDs cannot lose delivery")
        precondition(!cursor.accept(id: 3, deliveredAt: 1_030, now: now), "Reject future records")
        precondition(!cursor.accept(id: 4, deliveredAt: 1_005, now: start.addingTimeInterval(200)), "Drop stale pending delivery")
        print("PASS: foreground app and helper suppression, generic app parsing, malformed records, FIFO, deduplication, delayed dismissal, overflow, filters, delivery timing")
    }
}
