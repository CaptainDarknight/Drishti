import Foundation
import UserNotifications
import OSLog

final class WatchVibrationManager: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.example.safepath", category: "Alerts")
    private var timer: DispatchSourceTimer?
    private var interval: TimeInterval?
    private var authorized = false
    override init() { super.init(); center.delegate = self }
    func requestPermission(completion: ((Bool) -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            self?.authorized = granted
            self?.logger.info("Notification permission granted: \(granted)")
            DispatchQueue.main.async { completion?(granted) }
        }
    }
    func update(distanceMeters: Double?) {
        let next: TimeInterval?
        if let distanceMeters, distanceMeters < 1 { next = 1 } // iOS local-notification triggers are at least one second.
        else if let distanceMeters, distanceMeters <= 2 { next = 1 }
        else if let distanceMeters, distanceMeters <= 3 { next = 2 }
        else { next = nil }
        guard interval != next else { return }
        interval = next
        timer?.cancel(); timer = nil
        guard let next else { return }
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + next, repeating: next)
        source.setEventHandler { [weak self] in self?.schedulePulse(test: false) }
        timer = source; source.resume()
    }
    func sendTestPulse() { schedulePulse(test: true) }
    private func schedulePulse(test: Bool) {
        guard authorized else { return }
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let active = requests.filter { $0.identifier.hasPrefix("safepath-pulse-") }.map(\.identifier)
            if !test && !active.isEmpty { return } // Keep no more than one pulse pending.
            self.center.removePendingNotificationRequests(withIdentifiers: active)
            let content = UNMutableNotificationContent()
            content.title = test ? "Drishit test pulse" : "Drishit obstacle alert"
            content.body = test ? "If notifications are mirrored, your watch may vibrate." : "Obstacle nearby. Check your path."
            content.sound = .default
            if #available(iOS 15.0, *) { content.interruptionLevel = .active }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: "safepath-pulse-\(UUID().uuidString)", content: content, trigger: trigger)
            self.center.add(request) { error in
                if let error { self.logger.error("Could not schedule local alert: \(error.localizedDescription, privacy: .public)") }
            }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
