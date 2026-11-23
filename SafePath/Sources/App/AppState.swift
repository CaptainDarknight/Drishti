import Foundation
import CoreLocation
import SwiftUI
import UIKit

struct RoutePoint: Codable, Identifiable {
    var id = UUID()
    var tripID: UUID
    var latitude: Double
    var longitude: Double
    var date: Date = .now
    var event: String?
    var distance: Double?
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    init(_ coordinate: CLLocationCoordinate2D, tripID: UUID, event: String? = nil, distance: Double? = nil) {
        id = UUID(); self.tripID = tripID
        latitude = coordinate.latitude; longitude = coordinate.longitude; self.event = event; self.distance = distance
    }
}

@MainActor final class AppState: ObservableObject {
    @Published var destination = ""
    @Published var isTripActive = false
    @Published var isCameraActive = false
    @Published var latestObstacle = "Camera off"
    @Published var distanceText = "Distance unavailable"
    @Published var direction = "Ahead"
    @Published var detections: [DetectedObject] = []
    @Published var breadcrumbs: [RoutePoint] = []
    @Published var voiceEnabled = true {
        didSet { if !voiceEnabled { voice.pause() } }
    }
    @Published var vibrationEnabled = true {
        didSet { if !vibrationEnabled { alerts.update(distanceMeters: nil) } }
    }
    @Published var overlayEnabled = true
    @Published var stealthEnabled = false
    @Published var audioStatus: String?
    @Published var permissionMessage: String?
    @Published var isListeningForDestination = false
    @Published var savedHome: CLLocationCoordinate2D? {
        didSet {
            guard let savedHome else { return }
            UserDefaults.standard.set([savedHome.latitude, savedHome.longitude], forKey: "SafePath.home")
        }
    }
    private let location = LocationRecorder()
    let camera = CameraSession()
    let alerts = WatchVibrationManager()
    let voice = VoiceGuide()
    let audio = AudioSessionManager()
    let speechInput = SpeechRecognitionManager()
    private var lastVoice = Date.distantPast
    private var lastDetectionNote = Date.distantPast
    private var lastNotedObject: String?
    private var currentTripID = UUID()
    private var previousBrightness: CGFloat?

    init() {
        if let pair = UserDefaults.standard.array(forKey: "SafePath.home") as? [Double], pair.count == 2 {
            savedHome = CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
        if let points = RouteStorage.load() { breadcrumbs = points }
        if let rawID = UserDefaults.standard.string(forKey: "SafePath.currentTrip"), let id = UUID(uuidString: rawID) { currentTripID = id }
        else if let id = breadcrumbs.last?.tripID { currentTripID = id }
        location.onLocation = { [weak self] coordinate in
            guard let self, self.isTripActive else { return }
            self.appendRoutePoint(RoutePoint(coordinate, tripID: self.currentTripID))
        }
        location.onIssue = { [weak self] message in self?.permissionMessage = message }
        camera.onDetections = { [weak self] objects in self?.consume(objects) }
        speechInput.onText = { [weak self] text in self?.destination = text }
        speechInput.onError = { [weak self] text in self?.permissionMessage = text; self?.isListeningForDestination = false }
        speechInput.onFinish = { [weak self] in self?.isListeningForDestination = false; self?.audio.configure() }
        audio.onInterruption = { [weak self] interrupted in
            guard let self else { return }
            self.audioStatus = interrupted ? "Call active — voice guidance paused." : nil
            if interrupted { self.voice.pause() } else if self.voiceEnabled { self.voice.resume() }
        }
        audio.configure()
    }

    var routeKilometers: Double {
        let current = breadcrumbs.filter { $0.tripID == currentTripID }
        guard current.count > 1 else { return 0 }
        return zip(current, current.dropFirst()).reduce(0) { $0 + CLLocation(latitude: $1.0.latitude, longitude: $1.0.longitude).distance(from: CLLocation(latitude: $1.1.latitude, longitude: $1.1.longitude)) } / 1000
    }
    var currentTripObstacleCount: Int { breadcrumbs.filter { $0.tripID == currentTripID && $0.event != nil }.count }

    func startCamera() {
        isCameraActive = true
        latestObstacle = "Path clear"
        camera.start { [weak self] message in self?.permissionMessage = message }
    }
    func stopCamera() { isCameraActive = false; camera.stop(); alerts.update(distanceMeters: nil) }
    func appDidEnterBackground() { restoreBrightness(); stopCamera() }
    func startTrip() {
        let query = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { permissionMessage = "Enter a destination first."; return }
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if ["home", "go home", "take me home", "take me to home", "navigate home"].contains(normalized) {
            guard savedHome != nil else { permissionMessage = "Save your home location before asking Drishit to take you home."; return }
            goHome(); return
        }
        var destinationQuery = query
        for prefix in ["please take me to ", "can you take me to ", "i want to go to ", "take me to ", "navigate to ", "go to ", "directions to "] where normalized.hasPrefix(prefix) {
            destinationQuery = String(query.dropFirst(prefix.count))
            break
        }
        if destinationQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == "home" {
            guard savedHome != nil else { permissionMessage = "Save your home location before asking Drishit to take you home."; return }
            goHome(); return
        }
        guard !destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            permissionMessage = "Say or type a place name, such as “Take me to the library.”"; return
        }
        location.start { [weak self] authorized in
            guard let self, authorized else { return }
            if !self.isTripActive { self.beginNewTrip() }
            self.isTripActive = true
            MapsLink.open(destination: destinationQuery)
        }
    }
    func stopTrip() { isTripActive = false; location.stop() }
    func saveHomeAtCurrentLocation() {
        permissionMessage = "Finding your location to save as home…"
        location.requestCurrentLocation { [weak self] coordinate in
            self?.savedHome = coordinate
            self?.permissionMessage = "Home location saved on this iPhone."
        }
    }
    func goHome() {
        guard let savedHome else { permissionMessage = "Save your home location before asking for directions home."; return }
        location.start { [weak self] authorized in
            guard let self, authorized else { return }
            if !self.isTripActive { self.beginNewTrip() }
            self.isTripActive = true
            MapsLink.open(coordinate: savedHome)
        }
    }
    func testPulse() { alerts.sendTestPulse() }
    func enableNotifications() {
        alerts.requestPermission { [weak self] granted in
            self?.permissionMessage = granted ? "Notifications enabled. Huawei Health may mirror them to your watch." : "Notifications are off. Enable Drishit in iPhone Settings → Notifications to use watch mirroring."
        }
    }
    func toggleVoiceDestination() {
        if isListeningForDestination { speechInput.stop(); isListeningForDestination = false }
        else { isListeningForDestination = true; speechInput.start() }
    }
    func toggleStealth() {
        if !stealthEnabled { previousBrightness = UIScreen.main.brightness; UIScreen.main.brightness = 0.02 }
        else { UIScreen.main.brightness = previousBrightness ?? 0.5; previousBrightness = nil }
        stealthEnabled.toggle()
    }
    func restoreBrightness() {
        guard stealthEnabled else { return }
        UIScreen.main.brightness = previousBrightness ?? 0.5
        previousBrightness = nil
        stealthEnabled = false
    }

    private func consume(_ objects: [DetectedObject]) {
        detections = objects
        guard let closest = objects.filter({ $0.distanceMeters != nil }).min(by: { $0.distanceMeters! < $1.distanceMeters! }) else {
            latestObstacle = objects.isEmpty ? "Path clear" : "Object ahead"
            distanceText = "Distance unavailable"
            if vibrationEnabled { alerts.update(distanceMeters: nil) }
            return
        }
        let distance = closest.distanceMeters!
        direction = closest.horizontalPosition < 0.38 ? "Left" : (closest.horizontalPosition > 0.62 ? "Right" : "Ahead")
        latestObstacle = distance < 1 ? "Object very close" : "Object ahead"
        distanceText = String(format: "%.1f meters", distance)
        if isTripActive, let coordinate = location.lastCoordinate,
           Date().timeIntervalSince(lastDetectionNote) > 8 || lastNotedObject != closest.label {
            appendRoutePoint(RoutePoint(coordinate, tripID: currentTripID, event: closest.label, distance: distance))
            lastDetectionNote = .now; lastNotedObject = closest.label
        }
        alerts.update(distanceMeters: vibrationEnabled ? distance : nil)
        let urgent = distance < 1
        if voiceEnabled && audioStatus == nil && (Date().timeIntervalSince(lastVoice) > (urgent ? 2 : 4)) {
            voice.speak(distance: distance, direction: direction, urgent: urgent)
            lastVoice = .now
        }
    }
    private func appendRoutePoint(_ point: RoutePoint) {
        if let last = breadcrumbs.last, point.event == nil,
           CLLocation(latitude: point.latitude, longitude: point.longitude).distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude)) < 5 { return }
        breadcrumbs.append(point)
        if breadcrumbs.count > 5000 { breadcrumbs.removeFirst(breadcrumbs.count - 5000) }
        RouteStorage.save(breadcrumbs)
    }
    private func beginNewTrip() {
        currentTripID = UUID()
        UserDefaults.standard.set(currentTripID.uuidString, forKey: "SafePath.currentTrip")
        lastDetectionNote = .distantPast
        lastNotedObject = nil
    }
}

private enum RouteStorage {
    private static var fileURL: URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return directory.appendingPathComponent("SafePath", isDirectory: true).appendingPathComponent("route.json")
    }
    static func load() -> [RoutePoint]? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([RoutePoint].self, from: data)
    }
    static func save(_ points: [RoutePoint]) {
        guard let fileURL, let data = try? JSONEncoder().encode(points) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try? data.write(to: fileURL, options: .atomic)
    }
}

private final class LocationRecorder: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocation: ((CLLocationCoordinate2D) -> Void)?
    var onIssue: ((String) -> Void)?
    private var oneShot: ((CLLocationCoordinate2D) -> Void)?
    private var pendingStart: ((Bool) -> Void)?
    private var wantsUpdates = false
    var lastCoordinate: CLLocationCoordinate2D?
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation; manager.distanceFilter = 3 }
    func start(completion: @escaping (Bool) -> Void) {
        wantsUpdates = true
        pendingStart = completion
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            beginUpdates(always: true)
        case .authorizedWhenInUse:
            beginUpdates(always: false)
        default:
            onIssue?("Location access is off. Enable it in iPhone Settings to save your path.")
            finishStart(false)
        }
    }
    private func beginUpdates(always: Bool) {
        if always {
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.showsBackgroundLocationIndicator = true
        } else {
            onIssue?("Path recording works while Drishit is open. Set Location to Always to keep recording when Google Maps is open.")
        }
        manager.startUpdatingLocation()
        finishStart(true)
    }
    private func finishStart(_ success: Bool) { let completion = pendingStart; pendingStart = nil; completion?(success) }
    func stop() { wantsUpdates = false; manager.stopUpdatingLocation(); finishStart(false) }
    func requestCurrentLocation(_ completion: @escaping (CLLocationCoordinate2D) -> Void) {
        oneShot = completion
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: onIssue?("Location access is off. Enable it in iPhone Settings to save home."); oneShot = nil
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        lastCoordinate = coordinate; onLocation?(coordinate); oneShot?(coordinate); oneShot = nil
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways {
            if wantsUpdates { beginUpdates(always: true) }
            else if oneShot != nil { manager.requestLocation() }
        } else if manager.authorizationStatus == .authorizedWhenInUse {
            if pendingStart != nil { beginUpdates(always: false) }
            else if oneShot != nil { manager.requestLocation() }
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            onIssue?("Location access is off. Enable it in iPhone Settings to save your path.")
            oneShot = nil
            finishStart(false)
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        oneShot = nil
        onIssue?("Could not get your location. Check Location Services and try again.")
        finishStart(false)
    }
}

enum MapsLink {
    static func open(destination: String) {
        guard var components = URLComponents(string: "https://www.google.com/maps/dir/") else { return }
        components.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "destination", value: destination), URLQueryItem(name: "travelmode", value: "walking")]
        if let url = components.url { UIApplication.shared.open(url) }
    }
    static func open(coordinate: CLLocationCoordinate2D) {
        open(destination: "\(coordinate.latitude),\(coordinate.longitude)")
    }
}

