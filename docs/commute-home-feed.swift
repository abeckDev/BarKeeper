#!/usr/bin/env swift
//
// commute-home.swift — BarKeeper Feed Resource
//
// Calculates the driving duration from your current location to your home
// using Apple Maps (MapKit + CoreLocation) — no third-party dependencies.
//
// ── Requirements ─────────────────────────────────────────────────────────
//
//   - macOS 12+ (Monterey)
//   - Xcode Command Line Tools  →  xcode-select --install
//
// ── Setup ────────────────────────────────────────────────────────────────
//
//   1. Set your home address (add to ~/.zprofile, then restart your shell):
//
//        export HOME_ADDRESS="Your Street 1, City, Country"
//
//      If BarKeeper is a GUI app, also run (re-run after each reboot):
//
//        launchctl setenv HOME_ADDRESS "Your Street 1, City, Country"
//
//   2. Create the .app bundle (needed for macOS location permissions —
//      plain CLI scripts cannot request location access):
//
//        mkdir -p CommuteHome.app/Contents/MacOS
//
//      Then create CommuteHome.app/Contents/Info.plist with:
//
//        <?xml version="1.0" encoding="UTF-8"?>
//        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
//          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
//        <plist version="1.0">
//        <dict>
//            <key>CFBundleIdentifier</key>
//            <string>com.barkeeper.commute-home</string>
//            <key>CFBundleName</key>
//            <string>CommuteHome</string>
//            <key>CFBundleExecutable</key>
//            <string>commute-home</string>
//            <key>LSUIElement</key>
//            <true/>
//            <key>NSLocationUsageDescription</key>
//            <string>Calculates driving time to home.</string>
//            <key>NSLocationWhenInUseUsageDescription</key>
//            <string>Calculates driving time to home.</string>
//            <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
//            <string>Calculates driving time to home.</string>
//        </dict>
//        </plist>
//
//   3. Compile the binary into the app bundle:
//
//        swiftc commute-home.swift -o CommuteHome.app/Contents/MacOS/commute-home
//
//   4. Grant location permission by launching it once:
//
//        open CommuteHome.app
//
//      macOS will show a "CommuteHome wants to use your location" prompt.
//      Click Allow. After this, CommuteHome appears in:
//        System Settings → Privacy & Security → Location Services
//
//   5. Run it (e.g., from a launcher script for BarKeeper):
//
//        OUT=$(mktemp) && open --stdout "$OUT" --wait-apps CommuteHome.app && cat "$OUT"; rm "$OUT"
//
//      It must be launched via `open` so macOS uses the app bundle identity
//      for location access. Running the binary directly uses the calling
//      app's identity (e.g., Terminal), which may not have permission.
//
// ── Rebuilding ───────────────────────────────────────────────────────────
//
//   After editing this file, recompile:
//
//     swiftc commute-home.swift -o CommuteHome.app/Contents/MacOS/commute-home
//

import Foundation
import CoreLocation
import MapKit

// ── Configuration ────────────────────────────────────────────────────────────

let rawHomeAddress = ProcessInfo.processInfo.environment["HOME_ADDRESS"] ?? ""

// Guard against double-UTF-8 encoding (happens when launched via `open`)
let homeAddress: String = {
    if let data = rawHomeAddress.cString(using: .isoLatin1),
       let fixed = String(cString: data, encoding: .utf8) {
        return fixed
    }
    return rawHomeAddress
}()

guard !homeAddress.isEmpty else {
    fputs("Error: HOME_ADDRESS environment variable is not set.\n", stderr)
    fputs("Add this to your ~/.zprofile and reload it:\n", stderr)
    fputs("  export HOME_ADDRESS=\"Your Street 1, City, Country\"\n", stderr)
    exit(1)
}

// ── Cache (persist last duration across runs) ─────────────────────────────────

let cacheDir  = (NSHomeDirectory() as NSString)
    .appendingPathComponent(".cache/barkeeper")
let cacheFile = (cacheDir as NSString)
    .appendingPathComponent("commute_home_last_duration_minutes.txt")

try? FileManager.default.createDirectory(
    atPath: cacheDir, withIntermediateDirectories: true)

var lastDurationMinutes: Int? = {
    guard let raw = try? String(contentsOfFile: cacheFile, encoding: .utf8),
          let val = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    else { return nil }
    return val
}()

// ── Helpers ───────────────────────────────────────────────────────────────────

func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

func emitError(_ message: String) {
    fputs("Error: \(message)\n", stderr)
    // Exit non-zero so BarKeeper shows the error tooltip.
    exit(1)
}

func emitFeed(durationMinutes: Int) {
    // Persist for next run
    try? String(durationMinutes)
        .write(toFile: cacheFile, atomically: true, encoding: .utf8)

    // Build trend label
    let itemName:   String
    let itemDetail: String
    let isNew:      Bool

    if let last = lastDurationMinutes {
        let diff = durationMinutes - last
        switch diff {
        case let d where d > 0:
            itemName   = "🔴 \(durationMinutes) min  (▲ \(d) min slower than last check)"
            itemDetail = "Was \(last) min last time — traffic is worse right now."
            isNew      = true
        case let d where d < 0:
            itemName   = "🟢 \(durationMinutes) min  (▼ \(-d) min faster than last check)"
            itemDetail = "Was \(last) min last time — traffic is better right now."
            isNew      = false
        default:
            itemName   = "🟡 \(durationMinutes) min  (= same as last check)"
            itemDetail = "No change compared to the last check (\(last) min)."
            isNew      = false
        }
    } else {
        itemName   = "🚗 \(durationMinutes) min to home"
        itemDetail = "First measurement recorded — check again later to see the trend."
        isNew      = false
    }

    // Escape strings for JSON
    func jsonEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    let payload = """
    {
      "schemaVersion": 1,
      "title": "Drive Home",
      "checkedAt": "\(isoNow())",
      "items": [
        {
          "name": "\(jsonEscape(itemName))",
          "subtitle": "via Apple Maps · to: \(jsonEscape(homeAddress))",
          "detail": "\(jsonEscape(itemDetail))",
          "isNew": \(isNew ? "true" : "false")
        }
      ],
      "newCount": \(isNew ? 1 : 0)
    }
    """
    print(payload)
}

// ── Core orchestration ────────────────────────────────────────────────────────

final class CommuteRunner: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var didStartUpdating = false
    var isFinished = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            emitError(
                "Location access denied. Go to System Settings → Privacy & Security → " +
                "Location Services and allow access for CommuteHome (or BarKeeper)."
            )
        default:
            guard !didStartUpdating else { return }
            didStartUpdating = true
            manager.startUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !didStartUpdating else { return }
            didStartUpdating = true
            manager.startUpdatingLocation()
        case .denied, .restricted:
            emitError(
                "Location access denied. Go to System Settings → Privacy & Security → " +
                "Location Services and allow access for Terminal (or BarKeeper)."
            )
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let currentLocation = locations.last else { return }
        manager.stopUpdatingLocation()
        fetchDirections(from: currentLocation)
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        emitError("Could not determine your location: \(error.localizedDescription)")
    }

    // ── Directions ────────────────────────────────────────────────────────────

    private func fetchDirections(from origin: CLLocation) {
        CLGeocoder().geocodeAddressString(homeAddress) { placemarks, error in
            guard let homePlacemark = placemarks?.first else {
                emitError(
                    "Could not geocode HOME_ADDRESS \"\(homeAddress)\": " +
                    (error?.localizedDescription ?? "unknown error")
                )
                return
            }

            let request             = MKDirections.Request()
            request.source          = MKMapItem(
                placemark: MKPlacemark(coordinate: origin.coordinate))
            request.destination     = MKMapItem(
                placemark: MKPlacemark(placemark: homePlacemark))
            request.transportType   = .automobile
            request.departureDate   = Date()    // live traffic

            MKDirections(request: request).calculateETA { response, error in
                guard let response else {
                    emitError(
                        "Could not calculate route: " +
                        (error?.localizedDescription ?? "unknown error")
                    )
                    return
                }

                let minutes = Int((response.expectedTravelTime / 60).rounded())
                emitFeed(durationMinutes: minutes)
                self.isFinished = true
            }
        }
    }
}

// ── Entry point ───────────────────────────────────────────────────────────────

let runner = CommuteRunner()
runner.start()

// Keep the run loop alive until the async chain completes.
while !runner.isFinished {
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
}
