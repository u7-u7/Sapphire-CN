import Foundation

// Compile with the production XPCClient and HelperProtocol. These anonymous
// listeners never contact the privileged service or change system settings.
extension Notification.Name {
    static let sapphireHelperConnectionLost = Notification.Name("sapphireHelperConnectionLost")
    static let sapphireHelperConnectionRestored = Notification.Name("sapphireHelperConnectionRestored")
}

private final class FixtureHelper: NSObject {
    private let lock = NSLock()
    private var replyDelay: TimeInterval = 0
    private var repliesEnabled = true

    func configure(delay: TimeInterval = 0, repliesEnabled: Bool = true) {
        lock.lock()
        replyDelay = delay
        self.repliesEnabled = repliesEnabled
        lock.unlock()
    }

    @objc func getVersion(reply: @escaping (String) -> Void) {
        lock.lock()
        let delay = replyDelay
        let enabled = repliesEnabled
        lock.unlock()
        guard enabled else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { reply("fixture") }
    }

    @objc func getProtocolVersion(reply: @escaping (Int) -> Void) {
        reply(SapphireHelperProtocolVersion)
    }
}

private final class FixtureServer: NSObject, NSXPCListenerDelegate {
    let helper = FixtureHelper()
    private let listener = NSXPCListener.anonymous()
    private let lock = NSLock()
    private var connections: [NSXPCConnection] = []
    private var createdConnections = 0
    private let validationDelay: TimeInterval
    private let reject: Bool

    init(validationDelay: TimeInterval = 0, reject: Bool = false) {
        self.validationDelay = validationDelay
        self.reject = reject
        super.init()
        listener.delegate = self
        listener.resume()
    }

    func makeConnection() -> NSXPCConnection {
        lock.lock()
        createdConnections += 1
        lock.unlock()
        return NSXPCConnection(listenerEndpoint: listener.endpoint)
    }

    var connectionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return createdConnections
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Stand in for the real listener's synchronous strict signature check.
        Thread.sleep(forTimeInterval: validationDelay)
        guard !reject else { return false }
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = helper
        lock.lock()
        connections.append(connection)
        lock.unlock()
        connection.resume()
        return true
    }

    func invalidate() {
        listener.invalidate()
        lock.lock()
        let active = connections
        connections = []
        lock.unlock()
        active.forEach { $0.invalidate() }
    }
}

@main
struct VerifyHelperHandshake {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else { fatalError("FAIL: \(label)") }
        checks += 1
    }

    static func main() async throws {
        try await verifyConcurrentColdHandshake()
        await verifyBoundedTimeout()
        await verifyRejectedConnection()
        try await verifyShortHealthTimeoutAndLateReply()
        try await verifyReplacementConnection()
        print("PASS: \(checks) helper handshake checks using real anonymous XPC; no privileged calls")
    }

    static func verifyConcurrentColdHandshake() async throws {
        let realColdDelay = CommandLine.arguments.contains("--cold-start")
        let server = FixtureServer(validationDelay: realColdDelay ? 15 : 0.25)
        let client = XPCClient(initialHandshakeTimeout: realColdDelay ? 30 : 1, connectionFactory: server.makeConnection)
        defer { client.stop(); server.invalidate() }
        async let first = client.ping(timeout: 0.02)
        try await Task.sleep(for: .milliseconds(40))
        async let second = client.ping(timeout: 0.02)
        async let version = client.helperProtocolVersion(timeout: 0.02)
        let results = await (first, second, version)
        expect(results.0 && results.1, "concurrent short probes wait for cold validation")
        expect(results.2 == SapphireHelperProtocolVersion, "version probe shares cold handshake grace")
        expect(server.connectionCount == 1, "cold validation creates only one connection")
    }

    static func verifyBoundedTimeout() async {
        let server = FixtureServer()
        server.helper.configure(repliesEnabled: false)
        let client = XPCClient(initialHandshakeTimeout: 0.2, connectionFactory: server.makeConnection)
        defer { client.stop(); server.invalidate() }
        let start = ProcessInfo.processInfo.systemUptime
        let running = await client.ping(timeout: 0.02)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        expect(!running && elapsed >= 0.15 && elapsed < 1, "nonresponding helper has a bounded initial wait")
        let retryStart = ProcessInfo.processInfo.systemUptime
        let retry = await client.ping(timeout: 0.03)
        expect(!retry && ProcessInfo.processInfo.systemUptime - retryStart < 0.15, "later probes cannot renew initial grace")
        expect(server.connectionCount == 1, "a timeout preserves the connection instead of restarting validation")
    }

    static func verifyRejectedConnection() async {
        let server = FixtureServer(reject: true)
        let client = XPCClient(initialHandshakeTimeout: 3, connectionFactory: server.makeConnection)
        defer { client.stop(); server.invalidate() }
        let start = ProcessInfo.processInfo.systemUptime
        let running = await client.ping(timeout: 0.02)
        expect(!running && ProcessInfo.processInfo.systemUptime - start < 1, "explicit rejection fails before the grace deadline")
        let retry = await client.ping(timeout: 0.02)
        expect(!retry && server.connectionCount == 2, "actual XPC failure allows a fresh connection")
    }

    static func verifyShortHealthTimeoutAndLateReply() async throws {
        let server = FixtureServer()
        let client = XPCClient(initialHandshakeTimeout: 1, connectionFactory: server.makeConnection)
        defer { client.stop(); server.invalidate() }
        let initial = await client.ping(timeout: 0.02)
        expect(initial, "initial handshake succeeds")
        server.helper.configure(delay: 0.15)
        let start = ProcessInfo.processInfo.systemUptime
        let slow = await client.ping(timeout: 0.03)
        expect(!slow && ProcessInfo.processInfo.systemUptime - start < 0.12, "verified connections retain short health timeouts")
        try await Task.sleep(for: .milliseconds(200))
        server.helper.configure()
        let recovered = await client.ping(timeout: 0.1)
        expect(recovered && server.connectionCount == 1, "late reply completes once and the same connection stays usable")
    }

    static func verifyReplacementConnection() async throws {
        let server = FixtureServer()
        server.helper.configure(delay: 0.15)
        let client = XPCClient(initialHandshakeTimeout: 1, connectionFactory: server.makeConnection)
        defer { client.stop(); server.invalidate() }
        async let old = client.ping(timeout: 0.02)
        try await Task.sleep(for: .milliseconds(40))
        client.start(force: true)
        let oldResult = await old
        expect(!oldResult, "replacing a connection rejects the old pending probe")
        server.helper.configure()
        let newResult = await client.ping(timeout: 0.1)
        expect(newResult && server.connectionCount == 2, "explicit reset establishes a fresh verified connection")
        try await Task.sleep(for: .milliseconds(200))
        let stillRunning = await client.ping(timeout: 0.1)
        expect(stillRunning && server.connectionCount == 2, "old late reply cannot detach the replacement")
    }
}
