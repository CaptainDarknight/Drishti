import Foundation
import CoreLocation
import SwiftUI
import UIKit
import CoreMotion

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
    @Published var stepCount: Int?
    @Published var pedometerAvailable = CMPedometer.isStepCountingAvailable()
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
    private let pedometer = PedometerRecorder()
    let camera = CameraSession()
    let alerts = WatchVibrationManager()
    let voice = VoiceGuide()
    let audio = AudioSessionManager()
    let speechInput = SpeechRecognitionManager()
    private var lastVoice = Date.distantPast
    private var lastDetectionNote = Date.distantPast
    private var lastNotedObject: String?
    private var currentTripID = UUID()
    private var currentTripStartedAt = Date()
    private var previousBrightness: CGFloat?

    init() {
        if let pair = UserDefaults.standard.array(forKey: "SafePath.home") as? [Double], pair.count == 2 {
            savedHome = CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
        if let points = RouteStorage.load() { breadcrumbs = points }
        if let rawID = UserDefaults.standard.string(forKey: "SafePath.currentTrip"), let id = UUID(uuidString: rawID) { currentTripID = id }
        else if let id = breadcrumbs.last?.tripID { currentTripID = id }
        if let startedAt = UserDefaults.standard.object(forKey: "SafePath.currentTripStartedAt") as? Date { currentTripStartedAt = startedAt }
        stepCount = UserDefaults.standard.object(forKey: "SafePath.steps.\(currentTripID.uuidString)") as? Int
        location.onLocation = { [weak self] coordinate in
            guard let self, self.isTripActive else { return }
            self.appendRoutePoint(RoutePoint(coordinate, tripID: self.currentTripID))
        }
        location.onIssue = { [weak self] message in self?.permissionMessage = message }
        pedometer.onSteps = { [weak self] steps in
            guard let self else { return }
            self.stepCount = steps
            UserDefaults.standard.set(steps, forKey: "SafePath.steps.\(self.currentTripID.uuidString)")
        }
        pedometer.onIssue = { [weak self] message in self?.permissionMessage = message }
        camera.onDetections = { [weak self] objects in self?.consume(objects) }
        speechInput.onText = { [weak self] text in self?.destination = text }
        speechInput.onFinalText = { [weak self] text in
            guard let self else { return }
            self.destination = text
            self.startTrip()
        }
        speechInput.onError = { [weak self] text in
            self?.permissionMessage = text
            self?.isListeningForDestination = false
            self?.audio.configure()
        }
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
        guard !isCameraActive else { return }
        isCameraActive = true
        latestObstacle = "Path clear"
        camera.start { [weak self] message in
            guard let self else { return }
            self.permissionMessage = message
            if message != nil { self.isCameraActive = false }
        }
    }
    func stopCamera() { isCameraActive = false; camera.stop(); alerts.update(distanceMeters: nil) }
    func appDidEnterBackground() { restoreBrightness(); stopCamera() }
    func startTrip() {
        let query = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { permissionMessage = "Enter a destination first."; return }
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if ["home", "go home", "take me home", "take me to home", "navigate home"].contains(normalized) {
            guard savedHome != nil else { permissionMessage = "Save your home location before asking Drishti to take you home."; return }
            goHome(); return
        }
        var destinationQuery = query
        for prefix in ["please take me to ", "can you take me to ", "i want to go to ", "take me to ", "navigate to ", "go to ", "directions to "] where normalized.hasPrefix(prefix) {
            destinationQuery = String(query.dropFirst(prefix.count))
            break
        }
        if destinationQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == "home" {
            guard savedHome != nil else { permissionMessage = "Save your home location before asking Drishti to take you home."; return }
            goHome(); return
        }
        guard !destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            permissionMessage = "Say or type a place name, such as “Take me to the library.”"; return
        }
        beginTripIfNeeded()
        isTripActive = true
        pedometer.start(from: currentTripStartedAt)
        location.start { [weak self] authorized in
            guard let self else { return }
            if !authorized {
                self.permissionMessage = "Google Maps will open. Allow location access to record this walk in Drishti."
            }
            MapsLink.open(destination: destinationQuery) { opened in
                if !opened { self.permissionMessage = "Could not open Google Maps. Check your internet connection and try again." }
            }
        }
    }
    func stopTrip() { isTripActive = false; location.stop(); pedometer.stop() }
    func saveHomeAtCurrentLocation() {
        permissionMessage = "Finding your location to save as home…"
        location.requestCurrentLocation { [weak self] coordinate in
            self?.savedHome = coordinate
            self?.permissionMessage = "Home location saved on this iPhone."
        }
    }
    func goHome() {
        guard let savedHome else { permissionMessage = "Save your home location before asking for directions home."; return }
        beginTripIfNeeded()
        isTripActive = true
        pedometer.start(from: currentTripStartedAt)
        location.start { [weak self] authorized in
            guard let self else { return }
            if !authorized {
                self.permissionMessage = "Google Maps will open. Allow location access to record this walk in Drishti."
            }
            MapsLink.open(coordinate: savedHome) { opened in
                if !opened { self.permissionMessage = "Could not open Google Maps. Check your internet connection and try again." }
            }
        }
    }
    func testPulse() { alerts.sendTestPulse() }
    func enableNotifications() {
        alerts.requestPermission { [weak self] granted in
            self?.permissionMessage = granted ? "Notifications enabled. Your watch may mirror Drishti alerts." : "Notifications are off. Allow Drishti notifications in Settings to use watch mirroring."
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
        guard !objects.isEmpty else {
            latestObstacle = "Path clear"
            distanceText = "No object detected"
            if vibrationEnabled { alerts.update(distanceMeters: nil) }
            return
        }
        let closestWithDepth = objects.compactMap { object -> (DetectedObject, Double)? in
            guard let distance = object.distanceMeters, distance.isFinite, distance > 0 else { return nil }
            return (object, distance)
        }.min { $0.1 < $1.1 }
        guard let (closest, distance) = closestWithDepth else {
            guard let likelyNearest = objects.max(by: { $0.box.height < $1.box.height }) else { return }
            direction = likelyNearest.horizontalPosition < 0.38 ? "Left" : (likelyNearest.horizontalPosition > 0.62 ? "Right" : "Ahead")
            latestObstacle = likelyNearest.label
            distanceText = "Distance unavailable"
            if vibrationEnabled { alerts.update(distanceMeters: nil, apparentSize: likelyNearest.box.height) }
            if isTripActive, let coordinate = location.lastCoordinate,
               Date().timeIntervalSince(lastDetectionNote) > 8 || lastNotedObject != likelyNearest.label {
                appendRoutePoint(RoutePoint(coordinate, tripID: currentTripID, event: likelyNearest.label))
                lastDetectionNote = .now; lastNotedObject = likelyNearest.label
            }
            if voiceEnabled && audioStatus == nil && Date().timeIntervalSince(lastVoice) > 3 {
                voice.speakUnknown(direction: direction)
                lastVoice = .now
            }
            return
        }
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
    private func beginTripIfNeeded() {
        guard !isTripActive else { return }
        currentTripID = UUID()
        UserDefaults.standard.set(currentTripID.uuidString, forKey: "SafePath.currentTrip")
        currentTripStartedAt = .now
        UserDefaults.standard.set(currentTripStartedAt, forKey: "SafePath.currentTripStartedAt")
        stepCount = nil
        UserDefaults.standard.removeObject(forKey: "SafePath.steps.\(currentTripID.uuidString)")
        lastDetectionNote = .distantPast
        lastNotedObject = nil
    }
}

private final class PedometerRecorder {
    private let pedometer = CMPedometer()
    private var startDate: Date?
    var onSteps: ((Int) -> Void)?
    var onIssue: ((String) -> Void)?
    func start(from startDate: Date) {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.stopUpdates()
        self.startDate = startDate
        pedometer.startUpdates(from: startDate) { [weak self] data, error in
            if error != nil {
                DispatchQueue.main.async { self?.onIssue?("Allow Motion & Fitness access to count steps for this walk.") }
                return
            }
            guard let steps = data?.numberOfSteps.intValue else { return }
            DispatchQueue.main.async { self?.onSteps?(steps) }
        }
    }
    func stop() {
        pedometer.stopUpdates()
        guard let startDate else { return }
        self.startDate = nil
        pedometer.queryPedometerData(from: startDate, to: .now) { [weak self] data, error in
            if error != nil {
                DispatchQueue.main.async { self?.onIssue?("Could not read step totals. Check Motion & Fitness access in Settings.") }
                return
            }
            guard let steps = data?.numberOfSteps.intValue else { return }
            DispatchQueue.main.async { self?.onSteps?(steps) }
        }
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
    private var oneShotTimeout: DispatchWorkItem?
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
            onIssue?("Path recording works while Drishti is open. Set Location to Always to keep recording when Google Maps is open.")
        }
        manager.startUpdatingLocation()
        finishStart(true)
    }
    private func finishStart(_ success: Bool) { let completion = pendingStart; pendingStart = nil; completion?(success) }
    func stop() {
        wantsUpdates = false
        oneShot = nil
        oneShotTimeout?.cancel(); oneShotTimeout = nil
        manager.stopUpdatingLocation()
        finishStart(false)
    }
    func requestCurrentLocation(_ completion: @escaping (CLLocationCoordinate2D) -> Void) {
        oneShotTimeout?.cancel()
        oneShot = completion
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: beginOneShotUpdates()
        default: onIssue?("Location access is off. Enable it in iPhone Settings to save home."); oneShot = nil
        }
    }
    private func beginOneShotUpdates() {
        guard oneShot != nil else { return }
        oneShotTimeout?.cancel()
        manager.startUpdatingLocation()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.oneShot != nil else { return }
            self.oneShot = nil
            self.oneShotTimeout = nil
            if !self.wantsUpdates { self.manager.stopUpdatingLocation() }
            self.onIssue?("Could not get a GPS fix. Move outdoors, check Location Services, and try saving home again.")
        }
        oneShotTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeout)
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              Date().timeIntervalSince(location.timestamp) < 30 else { return }
        let coordinate = location.coordinate
        lastCoordinate = coordinate
        onLocation?(coordinate)
        if let oneShot {
            self.oneShot = nil
            oneShotTimeout?.cancel(); oneShotTimeout = nil
            if !wantsUpdates { manager.stopUpdatingLocation() }
            oneShot(coordinate)
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways {
            if wantsUpdates { beginUpdates(always: true) }
            else if oneShot != nil { beginOneShotUpdates() }
        } else if manager.authorizationStatus == .authorizedWhenInUse {
            if pendingStart != nil { beginUpdates(always: false) }
            else if oneShot != nil { beginOneShotUpdates() }
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            onIssue?("Location access is off. Enable it in iPhone Settings to save your path.")
            oneShot = nil
            oneShotTimeout?.cancel(); oneShotTimeout = nil
            finishStart(false)
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if oneShot != nil {
            // A transient GPS miss is common indoors; keep location updates alive until timeout.
            return
        }
        onIssue?("Could not get your location. Check Location Services and try again.")
        finishStart(false)
    }
}

enum MapsLink {
    static func open(destination: String, completion: ((Bool) -> Void)? = nil) {
        guard var components = URLComponents(string: "https://www.google.com/maps/dir/") else { completion?(false); return }
        components.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "destination", value: destination), URLQueryItem(name: "travelmode", value: "walking"), URLQueryItem(name: "dir_action", value: "navigate")]
        guard let url = components.url else { completion?(false); return }
        UIApplication.shared.open(url, options: [:]) { opened in
            DispatchQueue.main.async { completion?(opened) }
        }
    }
    static func open(coordinate: CLLocationCoordinate2D, completion: ((Bool) -> Void)? = nil) {
        open(destination: "\(coordinate.latitude),\(coordinate.longitude)", completion: completion)
    }
}

