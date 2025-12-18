//
//  SessionTimeoutManager.swift
//  Shelly
//
//  Manages session timeout and auto-lock functionality
//

import Foundation
import UIKit

@Observable
final class SessionTimeoutManager {
    static let shared = SessionTimeoutManager()

    // Configuration
    var isEnabled: Bool = false
    var timeoutSeconds: Int = 300  // 5 minutes default

    // State
    private(set) var isTimedOut: Bool = false
    private(set) var lastActivityTime: Date = Date()

    // Timer
    private var checkTimer: Timer?

    // Callbacks
    var onSessionTimeout: (() -> Void)?

    private init() {
        setupNotifications()
    }

    deinit {
        stopMonitoring()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Configuration

    func configure(enabled: Bool, timeoutSeconds: Int) {
        self.isEnabled = enabled
        self.timeoutSeconds = timeoutSeconds

        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
            isTimedOut = false
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard isEnabled else { return }

        stopMonitoring()
        recordActivity()

        // Check every 10 seconds
        checkTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkTimeout()
        }
    }

    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    // MARK: - Activity Tracking

    /// Call this whenever there's user activity
    func recordActivity() {
        lastActivityTime = Date()
        if isTimedOut {
            isTimedOut = false
        }
    }

    /// Reset timeout state after re-authentication
    func resetTimeout() {
        isTimedOut = false
        recordActivity()
    }

    // MARK: - Private

    private func checkTimeout() {
        guard isEnabled else { return }

        let elapsed = Date().timeIntervalSince(lastActivityTime)
        if elapsed > TimeInterval(timeoutSeconds) && !isTimedOut {
            triggerTimeout()
        }
    }

    private func triggerTimeout() {
        isTimedOut = true
        onSessionTimeout?()
    }

    private func setupNotifications() {
        // Check timeout when app becomes active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        // Pause timer when app enters background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        // Resume timer when app returns to foreground
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        checkTimeout()
    }

    @objc private func appDidEnterBackground() {
        // Timer continues tracking time but we don't need to actively check
        checkTimer?.invalidate()
        checkTimer = nil
    }

    @objc private func appWillEnterForeground() {
        // Check immediately when returning
        checkTimeout()

        // Restart periodic checks if still enabled and not timed out
        if isEnabled && !isTimedOut {
            checkTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                self?.checkTimeout()
            }
        }
    }
}

// MARK: - Convenience

extension SessionTimeoutManager {
    /// Time remaining until timeout (in seconds)
    var timeRemaining: TimeInterval {
        guard isEnabled else { return .infinity }
        let elapsed = Date().timeIntervalSince(lastActivityTime)
        return max(0, TimeInterval(timeoutSeconds) - elapsed)
    }

    /// Formatted time remaining
    var timeRemainingFormatted: String {
        let remaining = timeRemaining
        if remaining == .infinity {
            return "Disabled"
        }
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
