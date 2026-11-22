import Foundation
import Darwin

public protocol LeaseStoring: AnyObject {
    func load() throws -> SessionLease?
    func claim(_ lease: SessionLease) throws
    func save(_ lease: SessionLease?) throws
    func update(_ change: (inout SessionLease?) throws -> Void) throws
    func saveHealth(_ health: WatchdogHealth) throws
    func loadHealth() throws -> WatchdogHealth?
    func appendLog(_ line: String)
}

public extension LeaseStoring {
    func claim(_ lease: SessionLease) throws {
        try requireUnownedState(load())
        try save(lease)
    }

    func update(_ change: (inout SessionLease?) throws -> Void) throws {
        let before = try load()
        var after = before
        try change(&after)
        if before != after { try save(after) }
    }
}

private func requireUnownedState(_ existing: SessionLease?) throws {
    guard existing == nil else {
        throw LidAwakeError.invalidLease(
            "another session owns the sleep state or is waiting for recovery"
        )
    }
}

public final class FileLeaseStore: LeaseStoring {
    public let directory: URL
    public var leaseURL: URL { directory.appendingPathComponent("session.json") }
    public var healthURL: URL { directory.appendingPathComponent("watchdog-health.json") }
    public var logURL: URL { directory.appendingPathComponent("lidawake.log") }
    public var lockURL: URL { directory.appendingPathComponent("state.lock") }

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL? = nil) {
        let base = directory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LidAwake", isDirectory: true)
        self.directory = base

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() throws -> SessionLease? {
        guard fileManager.fileExists(atPath: directory.path) else { return nil }
        return try withLock { try readLease() }
    }

    public func claim(_ lease: SessionLease) throws {
        try ensureDirectory()
        try withLock {
            try requireUnownedState(readLease())
            try writeLease(lease)
        }
    }

    /// Keep ownership validation and changes to the shared sleep state under the same lock.
    public func update(_ change: (inout SessionLease?) throws -> Void) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try withLock {
            let before = try readLease()
            var after = before
            try change(&after)
            guard before != after else { return }
            if let after {
                try writeLease(after)
            } else {
                try fileManager.removeItem(at: leaseURL)
            }
        }
    }

    public func save(_ lease: SessionLease?) throws {
        if let lease {
            try ensureDirectory()
            try withLock { try writeLease(lease) }
        } else if fileManager.fileExists(atPath: directory.path) {
            try withLock {
                if fileManager.fileExists(atPath: leaseURL.path) {
                    try fileManager.removeItem(at: leaseURL)
                }
            }
        }
    }

    private func readLease() throws -> SessionLease? {
        guard fileManager.fileExists(atPath: leaseURL.path) else { return nil }
        let data = try Data(contentsOf: leaseURL)
        let lease = try decoder.decode(SessionLease.self, from: data)
        guard lease.version == SessionLease.currentVersion else {
            throw LidAwakeError.invalidLease("unsupported version \(lease.version)")
        }
        return lease
    }

    private func writeLease(_ lease: SessionLease) throws {
        let data = try encoder.encode(lease)
        try data.write(to: leaseURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: leaseURL.path)
    }

    public func saveHealth(_ health: WatchdogHealth) throws {
        try ensureDirectory()
        try withLock {
            let data = try encoder.encode(health)
            try data.write(to: healthURL, options: .atomic)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: healthURL.path)
        }
    }

    public func loadHealth() throws -> WatchdogHealth? {
        guard fileManager.fileExists(atPath: healthURL.path) else { return nil }
        return try withLock {
            return try decoder.decode(WatchdogHealth.self, from: Data(contentsOf: healthURL))
        }
    }

    public func clearAll() {
        try? fileManager.removeItem(at: directory)
    }

    public func appendLog(_ line: String) {
        try? ensureDirectory()
        let formatter = ISO8601DateFormatter()
        let entry = "\(formatter.string(from: Date())) \(line)\n"
        guard let data = entry.data(using: .utf8) else { return }
        if fileManager.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: logURL, options: .atomic)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)
        }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            throw LidAwakeError.invalidLease("cannot open state lock")
        }
        defer {
            _ = flock(fd, LOCK_UN)
            close(fd)
        }
        guard flock(fd, LOCK_EX) == 0 else {
            throw LidAwakeError.invalidLease("cannot acquire state lock")
        }
        return try body()
    }
}
