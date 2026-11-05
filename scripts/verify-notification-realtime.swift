// Run with NotificationRealtimeModel.swift. Optional: [sanitized-sample.json] [--expect-hideable].
// No titles or bodies are printed, including when a sample is supplied.
import Foundation

@main
struct VerifyNotificationRealtime {
    static let apps = [NotificationKnownApplication(identifier: "org.example.chat", displayNames: ["示例聊天", "Example Chat"]),
                       NotificationKnownApplication(identifier: "org.example.mail", displayNames: ["示例邮件"])]

    static func label(_ value: String, id: String = "") -> NotificationAXNode {
        NotificationAXNode(role: "AXStaticText", identifier: id, value: value)
    }

    static func banner(app: String = "org.example.chat", identifier: String = "1", title: String = "标题", body: String = "正文") -> NotificationAXNode {
        NotificationAXNode(role: "AXGroup", identifier: "notification-item:\(app):\(identifier)", children: [
            label(app == "org.example.chat" ? "示例聊天" : "示例邮件", id: "app-name"),
            label("12:34", id: "delivery-time"), label(title), label(body),
            NotificationAXNode(role: "AXButton", title: "关闭"),
            NotificationAXNode(role: "AXButton", title: "打开")
        ])
    }

    static func main() throws {
        let roundTrip = try JSONDecoder().decode(NotificationAXNode.self, from: JSONEncoder().encode(banner()))
        precondition(roundTrip == banner())
        let sparse = try JSONDecoder().decode(NotificationAXNode.self, from: Data(#"{"role":"AXStaticText","value":"fixture"}"#.utf8))
        precondition(sparse.value == "fixture" && sparse.children.isEmpty && sparse.identifier.isEmpty)
        let parsed = NotificationBannerParser.parse(root: banner(), knownApplications: apps)
        precondition(parsed.canHide && parsed.messages.count == 1)
        precondition(parsed.messages[0].appIdentifier == "org.example.chat")
        precondition(parsed.messages[0].title == "标题" && parsed.messages[0].body == "正文")
        precondition(parsed.messages[0].nativeIdentifier == "notification-item:org.example.chat:1")

        let actionWords = NotificationBannerParser.parse(root: banner(title: "打开", body: "关闭"), knownApplications: apps)
        precondition(actionWords.canHide && actionWords.messages[0].title == "打开" && actionWords.messages[0].body == "关闭")
        let clockBody = NotificationBannerParser.parse(root: banner(body: "12:34"), knownApplications: apps)
        precondition(clockBody.canHide && clockBody.messages[0].body == "12:34")

        let two = NotificationAXNode(role: "AXWindow", subrole: "AXSystemDialog", children: [banner(), banner(app: "org.example.mail", identifier: "2", title: "邮件", body: "第二条")])
        let pair = NotificationBannerParser.parse(root: two, knownApplications: apps)
        precondition(pair.canHide && pair.messages.count == 2)
        precondition(pair.messages.map(\.appIdentifier) == ["org.example.chat", "org.example.mail"])

        let unknown = NotificationAXNode(role: "AXGroup", identifier: "notification-item:org.unknown.app:3", children: [label("未知应用", id: "app-name"), label("标题"), label("正文")])
        let incompleteViewport = NotificationAXNode(role: "AXWindow", children: [banner(), unknown])
        let mixed = NotificationBannerParser.parse(root: incompleteViewport, knownApplications: apps)
        precondition(!mixed.canHide && mixed.messages.count == 1)
        precondition(!NotificationBannerParser.parse(root: unknown, knownApplications: apps).canHide)
        let unknownWithoutBannerID = NotificationAXNode(role: "AXGroup", children: [label("未知应用", id: "applicationName"), label("标题"), label("正文")])
        let mixedWithoutBannerID = NotificationAXNode(role: "AXWindow", children: [banner(), unknownWithoutBannerID])
        precondition(!NotificationBannerParser.parse(root: mixedWithoutBannerID, knownApplications: apps).canHide, "Unknown semantic source labels also block viewport hiding")
        let genericUnknown = NotificationAXNode(role: "AXGroup", identifier: "generic-container", children: [NotificationAXNode(role: "AXImage", description: "Unknown sender"), label("Unknown title"), label("Unknown body")])
        let mixedGeneric = NotificationAXNode(role: "AXWindow", children: [banner(), genericUnknown])
        precondition(!NotificationBannerParser.parse(root: mixedGeneric, knownApplications: apps).canHide, "Unconsumed text cannot be hidden just because its identifier lacks notification words")
        let unknownCombined = NotificationAXNode(role: "AXGroup", description: "Unknown notification combined description")
        precondition(!NotificationBannerParser.parse(root: NotificationAXNode(role: "AXWindow", children: [banner(), unknownCombined]), knownApplications: apps).canHide)
        let unknownActionWordBody = NotificationAXNode(role: "AXGroup", children: [label("现在"), label("打开")])
        precondition(!NotificationBannerParser.parse(root: NotificationAXNode(role: "AXWindow", children: [banner(), unknownActionWordBody]), knownApplications: apps).canHide)

        let nameOnly = NotificationAXNode(role: "AXGroup", identifier: "notification-item:visible", children: [label("示例聊天", id: "app-name"), label("标题"), label("正文")])
        precondition(NotificationBannerParser.parse(root: nameOnly, knownApplications: apps).canHide)
        let duplicateNames = apps + [NotificationKnownApplication(identifier: "org.example.clone", displayNames: ["示例聊天"])]
        let ambiguous = NotificationBannerParser.parse(root: nameOnly, knownApplications: duplicateNames)
        precondition(!ambiguous.canHide && ambiguous.failureReason == .ambiguousSource)
        let bodyAppName = NotificationAXNode(role: "AXGroup", identifier: "notification-item:unknown", children: [label("标题"), label("示例聊天")])
        precondition(!NotificationBannerParser.parse(root: bodyAppName, knownApplications: apps).canHide, "Body must not be used as app identity")
        let titleOnly = NotificationAXNode(role: "AXGroup", identifier: "notification-item:org.example.chat:4", children: [label("只有标题")])
        precondition(!NotificationBannerParser.parse(root: titleOnly, knownApplications: apps).canHide)
        let overlong = NotificationAXNode(role: "AXGroup", identifier: "notification-item:org.example.chat:5", children: [label("一"), label("二"), label("三"), label("四")])
        precondition(!NotificationBannerParser.parse(root: overlong, knownApplications: apps).canHide)
        let prefixApp = NotificationAXNode(role: "AXGroup", identifier: "notification-item:org.example.chat.Other:5", children: [label("标题"), label("正文")])
        precondition(!NotificationBannerParser.parse(root: prefixApp, knownApplications: apps).canHide)
        let hugeTree = NotificationAXNode(role: "AXWindow", children: (0..<801).map { label("\($0)") })
        precondition(NotificationBannerParser.parse(root: hugeTree, knownApplications: apps).failureReason == .limitExceeded)

        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        func event(_ channel: NotificationIngressChannel, _ id: String, _ time: Double, body: String = "好的", correlation: String? = nil) -> NotificationIngressEvent {
            NotificationIngressEvent(channel: channel, appIdentifier: "org.example.chat", title: "联系人", body: body,
                                     identifier: id, correlationIdentifier: correlation,
                                     deliveredAt: start.addingTimeInterval(time), observedAt: start.addingTimeInterval(time + (channel == .database ? 10 : 0.2)))
        }
        var deduper = NotificationIngressDeduplicator()
        precondition(deduper.shouldAccept(event(.native, "n1", 0), now: start))
        precondition(deduper.shouldAccept(event(.native, "n2", 0.3), now: start.addingTimeInterval(0.3)), "A second same-text native message must be accepted")
        precondition(!deduper.shouldAccept(event(.database, "d1", 0), now: start.addingTimeInterval(10)))
        precondition(!deduper.shouldAccept(event(.database, "d2", 0.3), now: start.addingTimeInterval(10.3)))
        precondition(deduper.shouldAccept(event(.database, "d3", 0.6), now: start.addingTimeInterval(10.6)), "One native event cannot suppress several DB events")
        precondition(!deduper.shouldAccept(event(.database, "d3", 0.6), now: start.addingTimeInterval(11)))
        precondition(deduper.shouldAccept(event(.native, "n2", 0.3, body: "更新正文"), now: start.addingTimeInterval(11.1)))
        precondition(!deduper.shouldAccept(event(.database, "d2", 0.3, body: "更新正文"), now: start.addingTimeInterval(11.2)))

        var stable = NotificationIngressDeduplicator()
        precondition(stable.shouldAccept(event(.native, "n", 0, correlation: "request-1"), now: start))
        let delayedDB = NotificationIngressEvent(channel: .database, appIdentifier: "org.example.chat", title: "联系人", body: "好的", identifier: "d", correlationIdentifier: "request-1", deliveredAt: start, observedAt: start.addingTimeInterval(30))
        precondition(!stable.shouldAccept(delayedDB, now: start.addingTimeInterval(30)), "Delayed commit is matched using the original delivery timestamp")
        precondition(stable.shouldAccept(event(.database, "other", 30, correlation: "request-2"), now: start.addingTimeInterval(30)))
        precondition(stable.shouldAccept(event(.native, "n", 0, correlation: "request-1"), now: start.addingTimeInterval(76)), "Expired state cannot swallow new data")
        var reused = NotificationIngressDeduplicator()
        precondition(reused.shouldAccept(event(.native, "n", 0, correlation: "reused"), now: start))
        precondition(reused.shouldAccept(event(.database, "new", 10, correlation: "reused"), now: start.addingTimeInterval(10)), "Reusing an identifier at a later delivery time is a new message")
        var bounded = NotificationIngressDeduplicator(maximumEntries: 2)
        for index in 0..<10 { _ = bounded.shouldAccept(event(.native, "\(index)", Double(index)), now: start.addingTimeInterval(Double(index))) }
        precondition(bounded.count == 2)
        print("PASS: synthetic source/boundary parsing, unknown and ambiguous preservation, one-to-one deduplication, revisions, retention, bounds and Codable round-trip")
        try inspectSampleIfProvided()
    }

    private static func inspectSampleIfProvided() throws {
        guard let path = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) else { return }
        let url = URL(fileURLWithPath: path)
        let length = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard length <= 2 * 1_024 * 1_024 else {
            throw NSError(domain: "NotificationSample", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sanitized sample exceeds the 2 MiB limit"])
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let roots: [NotificationAXNode]
        if let list = try? decoder.decode([NotificationAXNode].self, from: data) { roots = list }
        else { roots = [try decoder.decode(NotificationAXNode.self, from: data)] }
        let catalog = apps + [NotificationKnownApplication(identifier: "com.cshariq.sapphire", displayNames: ["Sapphire", "Sapphire-CN"])]
        for (index, root) in roots.enumerated() {
            let result = NotificationBannerParser.parse(root: root, knownApplications: catalog)
            print("SAMPLE[\(index)]: canHide=\(result.canHide) messages=\(result.messages.count) failure=\(result.failureReason?.rawValue ?? "none")")
            if CommandLine.arguments.contains("--expect-hideable"), !result.canHide {
                throw NSError(domain: "NotificationSample", code: 2, userInfo: [NSLocalizedDescriptionKey: "Controlled sample was not fully parseable: \(result.failureReason?.rawValue ?? "none")"])
            }
        }
    }
}
