import Foundation
import UserNotifications

/// Sends macOS User Notification Center alerts on behalf of BarKeeper.
///
/// ## Usage
///
/// Inject `NotificationService` into any component that needs to surface
/// system-level notifications:
///
/// ```swift
/// let notificationService = NotificationService()
///
/// // Request permission once at app startup
/// await notificationService.requestAuthorization()
///
/// // Send a notification
/// notificationService.notify(
///     title: "Script started",
///     message: "MyService is now running.",
///     type: .success
/// )
/// ```
///
/// ## Configuration
///
/// Notifications are only delivered when `enableNotifications` is `true` in
/// `AppConfiguration`. Toggle this flag in BarKeeper's Settings → General
/// panel. The preference is persisted to disk automatically.
///
/// ## Extensibility
///
/// `NotificationService` is a plain class with no SwiftUI dependencies.
/// Any future module (e.g. a scheduling engine or CLI helper) can create its
/// own instance or share the singleton stored on `ResourceManager`.
final class NotificationService: @unchecked Sendable {

    // MARK: - Types

    enum NotificationType {
        case success
        case error
    }

    // MARK: - Init

    init() {}

    // MARK: - Public API

    /// Requests the `alert` + `sound` notification authorisation from macOS.
    /// Call this once at app startup; macOS shows the system prompt only the
    /// first time (or after the user resets permissions in System Settings).
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Delivers a notification if the user has granted permission.
    ///
    /// - Parameters:
    ///   - title:   Bold heading shown in the notification banner.
    ///   - message: Supporting body text.
    ///   - type:    `.success` or `.error`; used to prefix the title with an
    ///              emoji for quick visual scanning.
    func notify(title: String, message: String, type: NotificationType = .success) {
        let prefix: String
        switch type {
        case .success: prefix = "✅"
        case .error:   prefix = "❌"
        }

        let content = UNMutableNotificationContent()
        content.title = "\(prefix) \(title)"
        content.body  = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil          // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("⚠️ NotificationService: failed to deliver notification – \(error)")
            }
        }
    }
}
