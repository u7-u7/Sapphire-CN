import Foundation

struct NotificationAXNode: Equatable, Codable {
    var role: String
    var subrole: String = ""
    var identifier: String = ""
    var title: String = ""
    var description: String = ""
    var value: String = ""
    var children: [NotificationAXNode] = []
}

extension NotificationAXNode {
    private enum CodingKeys: String, CodingKey {
        case role, subrole, identifier, title, description, value, children
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        role = try values.decode(String.self, forKey: .role)
        subrole = try values.decodeIfPresent(String.self, forKey: .subrole) ?? ""
        identifier = try values.decodeIfPresent(String.self, forKey: .identifier) ?? ""
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        value = try values.decodeIfPresent(String.self, forKey: .value) ?? ""
        children = try values.decodeIfPresent([NotificationAXNode].self, forKey: .children) ?? []
    }
}

struct NotificationKnownApplication: Equatable {
    let identifier: String
    let displayNames: [String]
}

struct NotificationRealtimeMessage: Equatable {
    let appIdentifier: String
    let title: String
    let body: String
    let nativeIdentifier: String?
}

enum NotificationBannerParseFailure: String, Equatable {
    case noNotification, unknownSource, ambiguousSource, ambiguousContent, incompleteContent, limitExceeded
}

struct NotificationBannerParseResult: Equatable {
    let messages: [NotificationRealtimeMessage]
    let canHide: Bool
    let failureReason: NotificationBannerParseFailure?
}

/// 只处理足够明确的通知结构。不能解析时保留系统横幅，不根据正文猜测来源应用。
enum NotificationBannerParser {
    private static let excludedRoles: Set<String> = [
        "AXButton", "AXMenuButton", "AXMenuItem", "AXCheckBox", "AXRadioButton",
        "AXPopUpButton", "AXDisclosureTriangle", "AXScrollBar", "AXToolbar",
        "AXTextField", "AXTextArea", "AXSearchField", "AXMenuBar", "AXMenu"
    ]
    private static let textRoles: Set<String> = ["AXStaticText", "AXHeading", "AXText"]
    private static let hostIdentifiers: Set<String> = ["com.apple.notificationcenterui", "com.apple.usernotificationcenter"]
    private struct WalkResult {
        var messages: [NotificationRealtimeMessage] = []
        var failure: NotificationBannerParseFailure?
    }
    private struct Leaf {
        let text: String
        let identifier: String
        let role: String
    }

    static func parse(root: NotificationAXNode, knownApplications: [NotificationKnownApplication]) -> NotificationBannerParseResult {
        guard isBounded(root) else {
            return NotificationBannerParseResult(messages: [], canHide: false, failureReason: .limitExceeded)
        }
        let apps = knownApplications.filter { !hostIdentifiers.contains($0.identifier.lowercased()) }
        var remaining = 800
        let result = walk(root, inheritedSource: nil, apps: apps, remaining: &remaining, depth: 0)
        let failure = result.failure ?? (result.messages.isEmpty ? .noNotification : nil)
        return NotificationBannerParseResult(messages: result.messages, canHide: failure == nil && !result.messages.isEmpty, failureReason: failure)
    }

    private static func isBounded(_ root: NotificationAXNode) -> Bool {
        var stack: [(NotificationAXNode, Int)] = [(root, 0)]
        var count = 0
        while let (node, depth) = stack.popLast() {
            count += 1
            guard count <= 800, depth < 16,
                  [node.identifier, node.title, node.description, node.value].allSatisfy({ $0.utf8.count <= 65_536 }),
                  node.children.count <= 800 - count - stack.count else { return false }
            stack += node.children.map { ($0, depth + 1) }
        }
        return true
    }

    private static func walk(_ node: NotificationAXNode, inheritedSource: String?, apps: [NotificationKnownApplication], remaining: inout Int, depth: Int) -> WalkResult {
        guard remaining > 0, depth < 16 else { return WalkResult(failure: .limitExceeded) }
        remaining -= 1
        guard !excludedRoles.contains(node.role) else { return WalkResult() }
        let ownSources = identifiers(in: [node.identifier], apps: apps)
        let inherited = ownSources.count == 1 ? ownSources.first : inheritedSource
        var children = WalkResult()
        var consumedChildren = Set<Int>()
        for (index, child) in node.children.enumerated() where !excludedRoles.contains(child.role) && !textRoles.contains(child.role) && child.role != "AXImage" {
            let result = walk(child, inheritedSource: inherited, apps: apps, remaining: &remaining, depth: depth + 1)
            children.messages += result.messages
            if !result.messages.isEmpty { consumedChildren.insert(index) }
            if result.failure == .limitExceeded { return WalkResult(failure: .limitExceeded) }
            if result.failure == .ambiguousSource { children.failure = .ambiguousSource }
            if result.failure == .unknownSource { children.failure = children.failure ?? .unknownSource }
            if isCandidateBoundary(child), let failure = result.failure { children.failure = children.failure ?? failure }
            if !result.messages.isEmpty, result.failure != nil { children.failure = result.failure }
        }
        if !children.messages.isEmpty {
            // 每个可见候选必须独立解析；不能隐藏仍含未知通知的整个 viewport。
            let directCandidateChildren = node.children.filter { isCandidateBoundary($0) }
            if directCandidateChildren.count > children.messages.count { children.failure = children.failure ?? .unknownSource }
            let parsedSources = Set(children.messages.map { $0.appIdentifier.lowercased() })
            let sourceNames = Set(apps.filter { parsedSources.contains($0.identifier.lowercased()) }.flatMap(\.displayNames).map(normalize))
            for (index, child) in node.children.enumerated() where !consumedChildren.contains(index) {
                if hasUnconsumedText(child, sourceNames: sourceNames, depth: 0) {
                    children.failure = children.failure ?? .ambiguousContent
                }
            }
            return children
        }
        return parseCandidate(node, inheritedSource: inherited, apps: apps)
    }

    private static func hasUnconsumedText(_ node: NotificationAXNode, sourceNames: Set<String>, depth: Int) -> Bool {
        guard depth < 16, !excludedRoles.contains(node.role) else { return false }
        let id = semanticIdentifier(node.identifier)
        let explicitTime = ["timestamp", "timelabel", "datelabel", "deliverytime"].contains(where: id.contains)
        if explicitTime || node.role == "AXDateTimeArea" { return false }
        let label = preferredText(node)
        let explicitSource = isSourceLabel(node.identifier) && sourceNames.contains(normalize(label))
        // 无语义标记的“应用名/现在/打开”等也可能是另一条通知的正文，不能按词面忽略。
        if !label.isEmpty, !explicitSource { return true }
        return node.children.contains { hasUnconsumedText($0, sourceNames: sourceNames, depth: depth + 1) }
    }

    private static func parseCandidate(_ node: NotificationAXNode, inheritedSource: String?, apps: [NotificationKnownApplication]) -> WalkResult {
        var leaves: [Leaf] = []
        var ids: [String] = []
        var sourceLabels: [String] = []
        collect(node, leaves: &leaves, identifiers: &ids, sourceLabels: &sourceLabels, depth: 0)
        guard !leaves.isEmpty else { return WalkResult() }
        var sourceIDs = identifiers(in: ids, apps: apps)
        if sourceIDs.isEmpty, let inheritedSource { sourceIDs.insert(inheritedSource) }
        if sourceIDs.count > 1 { return WalkResult(failure: .ambiguousSource) }
        if sourceIDs.isEmpty {
            let labelIDs = Set(sourceLabels.flatMap { label in applications(named: label, apps: apps).map(\.identifier) })
            guard labelIDs.count <= 1 else { return WalkResult(failure: .ambiguousSource) }
            sourceIDs = labelIDs
        }
        guard let source = sourceIDs.first else {
            return WalkResult(failure: isCandidateBoundary(node) || !sourceLabels.isEmpty ? .unknownSource : nil)
        }
        let names = Set(apps.filter { $0.identifier.caseInsensitiveCompare(source) == .orderedSame }
            .flatMap(\.displayNames).map(normalize))
        var content = leaves.map(\.text)
        if let first = content.first, names.contains(normalize(first)) { content.removeFirst() }
        // 两条标题-only 通知不能合并成一条“标题+正文”。重复来源头表示边界不明确。
        if content.contains(where: { names.contains(normalize($0)) }) {
            return WalkResult(failure: .ambiguousContent)
        }
        guard content.count >= 2 else { return WalkResult(failure: .incompleteContent) }
        guard content.count <= 3 else { return WalkResult(failure: .ambiguousContent) }
        let nativeIDs = Set(ids.filter { id in
            !id.isEmpty && id != source && containsIdentifier(id, source)
        })
        guard nativeIDs.count <= 1 else { return WalkResult(failure: .ambiguousContent) }
        let message = NotificationRealtimeMessage(appIdentifier: source, title: content[0],
                                                 body: content.dropFirst().joined(separator: "\n"),
                                                 nativeIdentifier: nativeIDs.first)
        return WalkResult(messages: [message])
    }

    private static func collect(_ node: NotificationAXNode, leaves: inout [Leaf], identifiers: inout [String], sourceLabels: inout [String], depth: Int) {
        guard depth < 16, !excludedRoles.contains(node.role) else { return }
        if !node.identifier.isEmpty { identifiers.append(node.identifier) }
        let label = preferredText(node)
        let identifier = node.identifier.lowercased()
        if isSourceLabel(identifier), !label.isEmpty { sourceLabels.append(label) }
        if node.role == "AXImage", !node.description.isEmpty, isSourceLabel(identifier) {
            sourceLabels.append(node.description)
        }
        if textRoles.contains(node.role), !label.isEmpty, !isTimestamp(node, text: label) {
            leaves.append(Leaf(text: label, identifier: node.identifier, role: node.role))
            return
        }
        for child in node.children { collect(child, leaves: &leaves, identifiers: &identifiers, sourceLabels: &sourceLabels, depth: depth + 1) }
    }

    private static func preferredText(_ node: NotificationAXNode) -> String {
        [node.value, node.title, node.description].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first(where: { !$0.isEmpty }) ?? ""
    }

    private static func isTimestamp(_ node: NotificationAXNode, text: String) -> Bool {
        let id = semanticIdentifier(node.identifier)
        if ["timestamp", "timelabel", "datelabel", "deliverytime"].contains(where: id.contains) { return true }
        return ["now", "just now", "刚刚", "现在"].contains(normalize(text))
    }

    private static func isSourceLabel(_ identifier: String) -> Bool {
        let id = semanticIdentifier(identifier)
        return ["appname", "applicationname", "appicon", "applicationicon", "sourcename", "sourceicon", "notificationsource"].contains(where: id.contains)
    }

    private static func semanticIdentifier(_ identifier: String) -> String {
        identifier.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func applications(named name: String, apps: [NotificationKnownApplication]) -> [NotificationKnownApplication] {
        apps.filter { $0.displayNames.contains { normalize($0) == normalize(name) } }
    }

    private static func identifiers(in values: [String], apps: [NotificationKnownApplication]) -> Set<String> {
        Set(apps.filter { app in values.contains { containsIdentifier($0, app.identifier) } }.map(\.identifier))
    }

    private static func containsIdentifier(_ value: String, _ identifier: String) -> Bool {
        let value = value.lowercased(), identifier = identifier.lowercased()
        guard !identifier.isEmpty else { return false }
        var search = value.startIndex..<value.endIndex
        while let range = value.range(of: identifier, range: search) {
            let before = range.lowerBound == value.startIndex ? nil : value[value.index(before: range.lowerBound)]
            let after = range.upperBound == value.endIndex ? nil : value[range.upperBound]
            let boundary: (Character?) -> Bool = { char in
                guard let char else { return true }
                return !char.isLetter && !char.isNumber && char != "." && char != "-" && char != "_"
            }
            if boundary(before), boundary(after) { return true }
            guard range.upperBound < value.endIndex else { break }
            search = range.upperBound..<value.endIndex
        }
        return false
    }

    private static func isCandidateBoundary(_ node: NotificationAXNode) -> Bool {
        guard !excludedRoles.contains(node.role) else { return false }
        let id = node.identifier.lowercased()
        return id.contains("banner") || id.contains("notification-item") || id.contains("notification-row") || node.subrole == "AXNotificationCenterAlert"
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased()
    }
}

enum NotificationIngressChannel: String, Equatable { case native, database }

struct NotificationIngressEvent: Equatable {
    let channel: NotificationIngressChannel
    let appIdentifier: String
    let title: String
    let body: String
    /// 此来源内的记录 ID，例如数据库 rec_id；不能假定可与 AX 标识直接比较。
    var identifier: String? = nil
    /// 只有确知两个来源使用同一命名空间时才提供，例如同一个 UN request identifier。
    var correlationIdentifier: String? = nil
    var deliveredAt: Date? = nil
    let observedAt: Date
}

/// 仅在内存中保留有界配对状态；跨来源按一对一匹配，不能把一条 native 吞掉多条 DB 消息。
struct NotificationIngressDeduplicator {
    private struct Entry {
        var events: [NotificationIngressEvent]
        var lastSeenAt: Date
    }
    private var entries: [Entry] = []
    private let retention: TimeInterval
    private let matchingWindow: TimeInterval
    private let timestampTolerance: TimeInterval
    private let maximumEntries: Int

    init(retention: TimeInterval = 45, matchingWindow: TimeInterval = 20, maximumEntries: Int = 512, timestampTolerance: TimeInterval = 2) {
        self.retention = max(1, retention)
        self.matchingWindow = max(0, matchingWindow)
        self.timestampTolerance = max(0, timestampTolerance)
        self.maximumEntries = max(1, maximumEntries)
    }

    var count: Int { entries.count }

    mutating func shouldAccept(_ event: NotificationIngressEvent, now: Date) -> Bool {
        entries.removeAll { now.timeIntervalSince($0.lastSeenAt) > retention }
        if let index = entries.firstIndex(where: { $0.events.contains(where: { isSameRevision($0, event) }) }) {
            var entry = entries.remove(at: index)
            entry.lastSeenAt = now
            entries.append(entry)
            return false
        }
        let matches = entries.indices.filter { index in
            !entries[index].events.contains(where: { $0.channel == event.channel })
                && entries[index].events.contains(where: { isCounterpart($0, event) })
        }
        if let index = matches.min(by: { distance(entries[$0].events[0], event) < distance(entries[$1].events[0], event) }) {
            var entry = entries.remove(at: index)
            entry.events.append(event)
            entry.lastSeenAt = now
            entries.append(entry)
            return false
        }
        if entries.count == maximumEntries { entries.removeFirst() }
        entries.append(Entry(events: [event], lastSeenAt: now))
        return true
    }

    private func isSameRevision(_ lhs: NotificationIngressEvent, _ rhs: NotificationIngressEvent) -> Bool {
        guard lhs.channel == rhs.channel, sameContent(lhs, rhs), lhs.deliveredAt == rhs.deliveredAt else { return false }
        if let lhsID = lhs.correlationIdentifier, let rhsID = rhs.correlationIdentifier { return lhsID == rhsID }
        if let lhsID = lhs.identifier, let rhsID = rhs.identifier { return lhsID == rhsID }
        return lhs == rhs
    }

    private func isCounterpart(_ lhs: NotificationIngressEvent, _ rhs: NotificationIngressEvent) -> Bool {
        guard lhs.channel != rhs.channel, sameContent(lhs, rhs) else { return false }
        if let lhsID = lhs.correlationIdentifier, let rhsID = rhs.correlationIdentifier {
            guard lhsID == rhsID else { return false }
        }
        // DB 提交晚不等于投递晚。只要有投递时间，就不能把重用同一 ID 的新消息当旧消息。
        let tolerance = lhs.deliveredAt != nil || rhs.deliveredAt != nil ? timestampTolerance : matchingWindow
        return distance(lhs, rhs) <= tolerance
    }

    private func sameContent(_ lhs: NotificationIngressEvent, _ rhs: NotificationIngressEvent) -> Bool {
        lhs.appIdentifier.caseInsensitiveCompare(rhs.appIdentifier) == .orderedSame && lhs.title == rhs.title && lhs.body == rhs.body
    }

    private func distance(_ lhs: NotificationIngressEvent, _ rhs: NotificationIngressEvent) -> TimeInterval {
        abs((lhs.deliveredAt ?? lhs.observedAt).timeIntervalSince(rhs.deliveredAt ?? rhs.observedAt))
    }
}
