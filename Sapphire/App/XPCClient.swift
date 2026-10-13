//
//  XPCClient.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-26

import Foundation

final class XPCClient {
    static let shared = XPCClient()

    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var failureNotificationSent = false
    private var firstHandshakeDeadline: TimeInterval?
    private var hasCompletedHandshake = false
    private let connectionFactory: () -> NSXPCConnection
    private let initialHandshakeTimeout: TimeInterval

    init(
        initialHandshakeTimeout: TimeInterval = 30,
        connectionFactory: @escaping () -> NSXPCConnection = {
            NSXPCConnection(machServiceName: "com.shariq.sapphireHelper", options: .privileged)
        }
    ) {
        self.initialHandshakeTimeout = initialHandshakeTimeout
        self.connectionFactory = connectionFactory
    }

    func proxy(onError: ((Error) -> Void)? = nil) -> HelperProtocol? {
        connectedProxy(onError: onError)?.helper
    }

    private func connectedProxy(onError: ((Error) -> Void)? = nil) -> (connection: NSXPCConnection, helper: HelperProtocol)? {
        start()

        lock.lock()
        let currentConnection = connection
        lock.unlock()
        guard let currentConnection else { return nil }

        let remoteObject = currentConnection.remoteObjectProxyWithErrorHandler { [weak self, weak currentConnection] error in
            if let currentConnection {
                self?.handleConnectionFailure(currentConnection)
            }
            onError?(error)
        }
        guard let helper = remoteObject as? HelperProtocol else { return nil }
        return (currentConnection, helper)
    }

    var helper: HelperProtocol? {
        proxy()
    }

    func start(force: Bool = false) {
        var oldConnection: NSXPCConnection?
        var newConnection: NSXPCConnection?

        lock.lock()
        if force {
            oldConnection = connection
            if let oldConnection {
                oldConnection.invalidationHandler = nil
                oldConnection.interruptionHandler = nil
            }
            connection = nil
        }

        if connection == nil {
            let candidate = connectionFactory()
            candidate.remoteObjectInterface = makeRemoteInterface()
            installHandlers(on: candidate)
            connection = candidate
            firstHandshakeDeadline = ProcessInfo.processInfo.systemUptime + initialHandshakeTimeout
            hasCompletedHandshake = false
            newConnection = candidate
        }
        lock.unlock()

        oldConnection?.invalidate()
        newConnection?.resume()
    }

    func stop() {
        lock.lock()
        let existing = connection
        if let existing {
            existing.invalidationHandler = nil
            existing.interruptionHandler = nil
        }
        connection = nil
        firstHandshakeDeadline = nil
        hasCompletedHandshake = false
        failureNotificationSent = false
        lock.unlock()

        existing?.invalidate()
    }

    func ping(timeout: TimeInterval = 5) async -> Bool {
        // A timeout does not prove the connection is broken: cold code-signing
        // validation can still be running. Only actual XPC errors detach it.
        await pingOnce(timeout: timeout)
    }

    func helperProtocolVersion(timeout: TimeInterval = 2) async -> Int? {
        await withCheckedContinuation { continuation in
            let stateLock = NSLock()
            var resumed = false

            func resumeOnce(_ value: Int?) {
                stateLock.lock()
                guard !resumed else {
                    stateLock.unlock()
                    return
                }
                resumed = true
                stateLock.unlock()
                continuation.resume(returning: value)
            }

            guard let remote = connectedProxy(onError: { _ in resumeOnce(nil) }) else {
                resumeOnce(nil)
                return
            }

            remote.helper.getProtocolVersion { [weak self] version in
                let current = self?.noteSuccessfulHandshake(on: remote.connection) == true
                resumeOnce(current ? version : nil)
            }

            let responseTimeout = responseTimeout(timeout, on: remote.connection)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + responseTimeout) {
                resumeOnce(nil)
            }
        }
    }

    private func pingOnce(timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            let stateLock = NSLock()
            var resumed = false

            func resumeOnce(_ value: Bool) {
                stateLock.lock()
                guard !resumed else {
                    stateLock.unlock()
                    return
                }
                resumed = true
                stateLock.unlock()
                continuation.resume(returning: value)
            }

            guard let remote = connectedProxy(onError: { _ in resumeOnce(false) }) else {
                resumeOnce(false)
                return
            }

            remote.helper.getVersion { [weak self] _ in
                resumeOnce(self?.noteSuccessfulHandshake(on: remote.connection) == true)
            }

            let responseTimeout = responseTimeout(timeout, on: remote.connection)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + responseTimeout) {
                resumeOnce(false)
            }
        }
    }

    private func responseTimeout(_ requestedTimeout: TimeInterval, on currentConnection: NSXPCConnection) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard connection === currentConnection, !hasCompletedHandshake,
              let firstHandshakeDeadline else {
            return requestedTimeout
        }
        // Concurrent health/startup requests share one monotonic deadline, so
        // repeated probes cannot extend the cold-start wait indefinitely.
        return max(requestedTimeout, firstHandshakeDeadline - ProcessInfo.processInfo.systemUptime)
    }

    private func makeRemoteInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: HelperProtocol.self)
        interface.setClasses(
            NSSet(array: [FanInfo.self, NSNull.self]) as! Set<AnyHashable>,
            for: #selector(HelperProtocol.getFanInfo(fanIndex:reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        return interface
    }

    private func installHandlers(on connection: NSXPCConnection) {
        connection.interruptionHandler = { [weak self, weak connection] in
            guard let connection else { return }
            connection.invalidationHandler = nil
            connection.interruptionHandler = nil
            self?.detach(connection, notifyLost: true)
            connection.invalidate()
        }
        connection.invalidationHandler = { [weak self, weak connection] in
            guard let connection else { return }
            connection.invalidationHandler = nil
            connection.interruptionHandler = nil
            self?.detach(connection, notifyLost: true)
        }
    }

    @discardableResult
    private func noteSuccessfulHandshake(on currentConnection: NSXPCConnection) -> Bool {
        var shouldNotify = false
        lock.lock()
        guard connection === currentConnection else {
            lock.unlock()
            return false
        }
        if !hasCompletedHandshake || failureNotificationSent {
            hasCompletedHandshake = true
            failureNotificationSent = false
            shouldNotify = true
        }
        lock.unlock()
        if shouldNotify {
            DispatchQueue.main.async { [weak self, weak currentConnection] in
                guard let self, let currentConnection else { return }
                self.lock.lock()
                let isCurrent = self.connection === currentConnection
                self.lock.unlock()
                guard isCurrent else { return }
                NotificationCenter.default.post(name: .sapphireHelperConnectionRestored, object: nil)
            }
        }
        return true
    }

    private func detach(_ failedConnection: NSXPCConnection, notifyLost: Bool) {
        var shouldNotify = false

        lock.lock()
        if connection === failedConnection {
            connection = nil
            firstHandshakeDeadline = nil
            hasCompletedHandshake = false
            if notifyLost, !failureNotificationSent {
                failureNotificationSent = true
                shouldNotify = true
            }
        }
        lock.unlock()

        if shouldNotify {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .sapphireHelperConnectionLost, object: nil)
            }
        }
    }

    private func handleConnectionFailure(_ failedConnection: NSXPCConnection) {
        failedConnection.invalidationHandler = nil
        failedConnection.interruptionHandler = nil
        detach(failedConnection, notifyLost: true)
        failedConnection.invalidate()
    }
}
