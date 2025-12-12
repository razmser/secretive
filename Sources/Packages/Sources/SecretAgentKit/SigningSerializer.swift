import Foundation
import OSLog

/// Serializes access to signing operations that would otherwise trigger interactive authentication.
actor SigningSerializer {

    private let logger = Logger(subsystem: "com.razmser.secretive.secretagent", category: "SigningSerializer")
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if !locked {
            locked = true
            return
        }
        logger.debug("Signing request queued (queueDepth: \(self.waiters.count + 1, privacy: .public))")
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        logger.debug("Signing request dequeued (remaining: \(self.waiters.count, privacy: .public))")
    }

    private func release() {
        guard !waiters.isEmpty else {
            locked = false
            return
        }
        logger.debug("Resuming queued signing request (remaining: \(self.waiters.count - 1, privacy: .public))")
        waiters.removeFirst().resume()
    }
}
