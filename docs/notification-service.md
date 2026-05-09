# Notification Service

BarKeeper utilizes macOS Notification Center alerts when toggle, button, or feed
actions complete (successfully or with an error). This document explains how the
service works and how other modules can use it.

---

## Architecture

```
NotificationService        (Sources/Utilities/NotificationService.swift)
        ↑
ResourceManager            (Sources/ViewModels/ResourceManager.swift)
        ↑
AppConfiguration           (Sources/Models/Resource.swift)
```

`NotificationService` is a plain Swift class with no SwiftUI dependency.
`ResourceManager` owns a private instance and gates delivery behind the
`enableNotifications` flag that is persisted in `AppConfiguration`.

---

## API

```swift
/// Request authorization from macOS (shown once per app install).
await notificationService.requestAuthorization()

/// Send a notification immediately.
notificationService.notify(
    title: "My Resource",
    message: "Action completed successfully.",
    type: .success   // or .error
)
```

`NotificationType`:

| Value      | Emoji prefix | Use case                      |
|------------|--------------|-------------------------------|
| `.success` | ✅           | Script ran and exited 0       |
| `.error`   | ❌           | Script failed or threw        |

---

## Configuration

Notifications are enabled by default. The user can opt out in
**Settings → Notifications** using the "Enable Notification Center alerts"
toggle. The preference is written to the BarKeeper config file
(`~/Library/Application Support/BarKeeper/config.json`) so it persists across
app restarts.

The relevant field in `AppConfiguration`:

```swift
struct AppConfiguration: Codable, Sendable {
    var enableNotifications: Bool   // defaults to true
    // …
}
```

Old config files that predate this field are automatically treated as
`enableNotifications: true` (opt-in on upgrade).

---

## When are notifications sent?

| Trigger                           | Condition      | Notification                                |
|-----------------------------------|----------------|---------------------------------------------|
| Toggle script succeeds            | exit code 0    | "Started/Stopped successfully."      |
| Toggle script fails               | exit code ≠ 0  | Error message from stderr (or exit code)    |
| Button action succeeds            | exit code 0    | "Action completed successfully."            |
| Button action fails               | exit code ≠ 0  | Error message from stderr (or exit code)    |
| Feed refresh: new items available | newCount > 0   | "N new item(s) available."                  |
| Feed refresh fails                | any error      | Error message                               |
| Missing script configuration      | —              | Configuration error message                 |

Notifications are **not** sent during background status polling
(`refreshAllStatuses`) to avoid noise when the app checks toggle states
periodically.

---

## Using the service in other modules

If a future module needs to send notifications, the recommended pattern is to
create a dedicated `NotificationService` instance (or share the one on
`ResourceManager` if appropriate):

```swift
import UserNotifications

final class MyModule {
    private let notifications = NotificationService()

    func doWork() async {
        // … perform work …
        notifications.notify(title: "My Module", message: "Done!", type: .success)
    }
}
```

`NotificationService` is marked `@unchecked Sendable` and is safe to use from
any Swift concurrency context.

---

## macOS Permissions

On first launch BarKeeper calls
`UNUserNotificationCenter.requestAuthorization(options: [.alert, .sound])`,
which shows the system permission prompt. If the user declines, no
notifications will be delivered regardless of the in-app toggle.

To reset permissions during development:

```bash
tccutil reset Notifications com.abeckdev.barkeeper
```
