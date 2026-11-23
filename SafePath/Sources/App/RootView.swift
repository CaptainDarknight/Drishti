import SwiftUI
import AVKit

enum AppTypography {
    static let fontName = "Inter-Regular"
}

private enum SafePalette {
    static let canvas = Color.white
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let muted = Color(red: 0.29, green: 0.31, blue: 0.34)
    static let blue = Color(red: 0.13, green: 0.15, blue: 0.19)
    static let surface = Color(red: 0.95, green: 0.96, blue: 0.97)
    static let mint = Color(red: 0.28, green: 0.73, blue: 0.63)
    static let orange = Color(red: 0.95, green: 0.60, blue: 0.28)
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingHelp = false
    @State private var showingCamera = false
    @State private var selectedTab = 0
    @State private var showingNotificationIntro = false
    @State private var showingConnections = false

    var body: some View {
        ZStack {
            SafePalette.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 19) {
                        header
                        if selectedTab == 0 { planner } else { tripOverview }
                        if let message = state.audioStatus { messageBanner(message) }
                        if let message = state.permissionMessage { messageBanner(message) }
                        Text("Drishti is an assistive tool. Keep using your usual mobility aid.")
                            .font(.custom(AppTypography.fontName, size: 13, relativeTo: .footnote)).foregroundStyle(SafePalette.muted).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 3).accessibilityLabel("Safety reminder. Drishti is an assistive tool. Continue using your usual mobility aid.")
                    }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)
                }
                bottomBar
            }
        }
        .font(.custom(AppTypography.fontName, size: 17, relativeTo: .body))
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingHelp) { HelpView().environmentObject(state) }
        .sheet(isPresented: $showingConnections) { DeviceConnectionsView().environmentObject(state) }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: { state.stopCamera() }) { cameraScreen }
        .alert("Enable safety alerts?", isPresented: $showingNotificationIntro) {
            Button("Enable notifications") { state.enableNotifications() }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("Drishti can send obstacle alerts to iPhone notifications. Huawei Health may mirror them to a paired watch when notification access is enabled.")
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = state.isCameraActive
            if !UserDefaults.standard.bool(forKey: "SafePath.notificationIntroShown") {
                UserDefaults.standard.set(true, forKey: "SafePath.notificationIntroShown")
                showingNotificationIntro = true
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { state.appDidEnterBackground(); UIApplication.shared.isIdleTimerDisabled = false }
            else if showingCamera { state.startCamera(); UIApplication.shared.isIdleTimerDisabled = true }
        }
        .onChange(of: state.isCameraActive) { active in
            UIApplication.shared.isIdleTimerDisabled = active && scenePhase == .active
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                Circle().fill(Color.white).frame(width: 46, height: 46)
                Image(systemName: "figure.walk").font(.system(size: 22, weight: .bold)).foregroundStyle(SafePalette.blue)
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Drishti").scaledFont(size: 23, weight: .heavy).foregroundStyle(SafePalette.ink)
                Text(greeting).scaledFont(size: 13, weight: .medium).foregroundStyle(SafePalette.muted)
            }.onTapGesture(count: 3) { showingCamera = true; state.startCamera() }
                .accessibilityHint("Triple tap to start obstacle awareness while Drishti is open.")
            Spacer()
            Button { showingConnections = true } label: {
                Image(systemName: "earbuds").font(.system(size: 18, weight: .semibold)).foregroundStyle(SafePalette.ink)
                    .frame(width: 46, height: 46).background(SafePalette.surface, in: Circle())
            }.accessibilityLabel("Connect earbuds or set up a watch")
            Button { showingHelp = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .semibold)).foregroundStyle(SafePalette.ink)
                    .frame(width: 48, height: 48).background(.white, in: Circle())
            }.accessibilityLabel("Settings and help")
        }
    }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        return hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
    }

    private var planner: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ready to go?").scaledFont(size: 32, weight: .heavy).foregroundStyle(SafePalette.ink).minimumScaleFactor(0.8).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "location.north.circle.fill").font(.system(size: 26)).foregroundStyle(SafePalette.mint).accessibilityHidden(true)
            }
            Text("Plan a walk or head to a saved place.").scaledFont(size: 16).foregroundStyle(SafePalette.muted)
            destinationEntry
            Button { state.startTrip() } label: {
                Label("Start walking route", systemImage: "map.fill").frame(maxWidth: .infinity).frame(minHeight: 62)
            }.buttonStyle(FilledButtonStyle(color: SafePalette.blue)).accessibilityHint("Opens a walking route in Google Maps and starts recording your path.")
            HStack(spacing: 11) {
                Button { state.saveHomeAtCurrentLocation() } label: {
                    Label("Save home", systemImage: "house.fill").frame(maxWidth: .infinity).frame(minHeight: 60)
                }.buttonStyle(SoftButtonStyle(color: SafePalette.blue))
                Button { state.goHome() } label: {
                    Label("Go home", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity).frame(minHeight: 60)
                }.buttonStyle(FilledButtonStyle(color: SafePalette.mint)).disabled(state.savedHome == nil).opacity(state.savedHome == nil ? 0.55 : 1)
            }
        }.padding(19).background(.white, in: RoundedRectangle(cornerRadius: 25)).shadow(color: .black.opacity(0.035), radius: 14, y: 5)
    }
    private var destinationEntry: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass").font(.system(size: 19, weight: .semibold)).foregroundStyle(SafePalette.blue)
            TextField("Where would you like to go?", text: $state.destination)
                .scaledFont(size: 17, weight: .medium).foregroundStyle(SafePalette.ink)
                .textInputAutocapitalization(.words).submitLabel(.go).accessibilityLabel("Destination")
            Button { state.toggleVoiceDestination() } label: {
                Image(systemName: state.isListeningForDestination ? "waveform.circle.fill" : "mic.fill")
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(state.isListeningForDestination ? SafePalette.orange : SafePalette.blue)
                    .frame(width: 46, height: 46)
            }.accessibilityLabel(state.isListeningForDestination ? "Stop listening for destination" : "Speak destination")
                .accessibilityHint("Uses speech recognition to fill in the destination field.")
        }.padding(.horizontal, 15).frame(minHeight: 60).background(SafePalette.surface, in: RoundedRectangle(cornerRadius: 15))
    }

    private var tripOverview: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(state.isTripActive ? "YOUR WALK" : "TRIP OVERVIEW").scaledFont(size: 12, weight: .bold).tracking(1.4).foregroundStyle(SafePalette.blue)
                    Text(String(format: "%.2f km", state.routeKilometers)).scaledFont(size: 36, weight: .heavy).foregroundStyle(SafePalette.ink)
                }
                Spacer()
                Image(systemName: "figure.walk.circle.fill").font(.system(size: 43)).foregroundStyle(SafePalette.mint).accessibilityHidden(true)
            }
            HStack(spacing: 10) {
                metric("Recorded points", value: "\(state.breadcrumbs.count)", icon: "mappin.and.ellipse", tint: SafePalette.blue)
                metric("Obstacle notes", value: "\(state.currentTripObstacleCount)", icon: "viewfinder", tint: SafePalette.orange)
            }
            awarenessSummary
            Button { showingConnections = true } label: {
                HStack(spacing: 13) {
                    Image(systemName: "earbuds").font(.system(size: 19, weight: .bold))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Audio & watch setup").scaledFont(size: 16, weight: .bold)
                        Text("Hear spoken direction cues · configure watch alerts").scaledFont(size: 12, weight: .medium).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                }.foregroundStyle(SafePalette.ink).padding(14).background(SafePalette.surface, in: RoundedRectangle(cornerRadius: 17))
            }.buttonStyle(.plain)
            HStack(spacing: 10) {
                Button { showingCamera = true; state.startCamera() } label: {
                    Label("Obstacle awareness", systemImage: "viewfinder").frame(maxWidth: .infinity).frame(minHeight: 62)
                }.buttonStyle(FilledButtonStyle(color: SafePalette.blue))
                Button { state.testPulse() } label: {
                    Label("Test pulse", systemImage: "waveform.path").frame(maxWidth: .infinity).frame(minHeight: 62)
                }.buttonStyle(SoftButtonStyle(color: SafePalette.blue))
            }
            Toggle(isOn: $state.voiceEnabled) {
                Label("Voice guidance", systemImage: "earbuds").scaledFont(size: 17, weight: .semibold).foregroundStyle(SafePalette.ink)
            }.tint(SafePalette.mint).padding(.vertical, 3)
            Toggle(isOn: $state.vibrationEnabled) {
                Label("Vibration alerts", systemImage: "applewatch").scaledFont(size: 17, weight: .semibold).foregroundStyle(SafePalette.ink)
            }.tint(SafePalette.mint).padding(.vertical, 3)
            Toggle(isOn: $state.overlayEnabled) {
                Label("Detection overlay", systemImage: "viewfinder.rectangular").scaledFont(size: 17, weight: .semibold).foregroundStyle(SafePalette.ink)
            }.tint(SafePalette.mint).padding(.vertical, 3)
            Button { state.isTripActive ? state.stopTrip() : state.startTrip() } label: {
                Label(state.isTripActive ? "Stop path recording" : "Continue in Google Maps", systemImage: state.isTripActive ? "stop.fill" : "arrow.up.right.square")
                    .frame(maxWidth: .infinity).frame(minHeight: 60)
            }.buttonStyle(SoftButtonStyle(color: SafePalette.blue))
        }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 25)).shadow(color: .black.opacity(0.035), radius: 14, y: 5)
    }
    private func metric(_ title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(tint)
            Text(value).scaledFont(size: 22, weight: .heavy).foregroundStyle(SafePalette.ink)
            Text(title).scaledFont(size: 13, weight: .medium).foregroundStyle(SafePalette.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(SafePalette.canvas, in: RoundedRectangle(cornerRadius: 17))
    }
    private var awarenessSummary: some View {
        HStack(spacing: 13) {
            ZStack { Circle().fill(SafePalette.mint.opacity(0.15)).frame(width: 50, height: 50); Image(systemName: "viewfinder").font(.system(size: 21, weight: .semibold)).foregroundStyle(SafePalette.mint) }
            VStack(alignment: .leading, spacing: 4) {
                Text(state.latestObstacle).scaledFont(size: 19, weight: .bold).foregroundStyle(SafePalette.ink)
                Text("\(state.distanceText) · \(state.direction)").scaledFont(size: 14, weight: .medium).foregroundStyle(SafePalette.muted)
            }
            Spacer(minLength: 0)
        }.padding(14).background(Color(red: 0.91, green: 0.97, blue: 0.95), in: RoundedRectangle(cornerRadius: 17))
            .accessibilityElement(children: .combine).accessibilityLabel("Obstacle status: \(state.latestObstacle), \(state.distanceText), \(state.direction)")
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            tabButton("Home", icon: "house.fill", index: 0)
            tabButton("My walks", icon: "eye.fill", index: 1)
        }.padding(.top, 10).padding(.bottom, 7).background(.white.shadow(.drop(color: .black.opacity(0.06), radius: 8, y: -3)))
    }
    private func tabButton(_ title: String, icon: String, index: Int) -> some View {
        Button { selectedTab = index } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                Text(title).scaledFont(size: 12, weight: .semibold)
            }.foregroundStyle(selectedTab == index ? SafePalette.blue : SafePalette.muted).frame(maxWidth: .infinity).frame(minHeight: 45)
        }.accessibilityAddTraits(selectedTab == index ? .isSelected : [])
    }
    private func messageBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(SafePalette.blue)
            Text(text).scaledFont(size: 14, weight: .medium).foregroundStyle(SafePalette.ink).fixedSize(horizontal: false, vertical: true)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 15))
    }
    private var cameraScreen: some View {
        ZStack(alignment: .top) {
            ARCameraView(camera: state.camera).ignoresSafeArea()
            if state.overlayEnabled { DetectionOverlayView(objects: state.detections).ignoresSafeArea() }
            VStack(spacing: 16) {
                HStack {
                    Button { showingCamera = false } label: { Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).frame(width: 52, height: 52).background(.black.opacity(0.65), in: Circle()) }
                        .accessibilityLabel("Close obstacle awareness")
                    Spacer()
                    Button { state.toggleStealth() } label: { Label(state.stealthEnabled ? "Restore screen" : "Dim screen", systemImage: "moon.fill").scaledFont(size: 15, weight: .bold).padding(.horizontal, 16).frame(minHeight: 52).background(.black.opacity(0.65), in: Capsule()) }
                        .accessibilityHint("Dims the display while camera processing continues.")
                }.foregroundStyle(.white).padding(.horizontal, 20).padding(.top, 12)
                if let message = state.permissionMessage {
                    Text(message).scaledFont(size: 15, weight: .semibold).foregroundStyle(.white)
                        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 20)
                }
                if let message = state.audioStatus {
                    Text(message).scaledFont(size: 15, weight: .semibold).foregroundStyle(.white)
                        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 20)
                }
                Spacer()
                HStack(spacing: 12) {
                    Image(systemName: "waveform").font(.system(size: 21, weight: .bold))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.latestObstacle).scaledFont(size: 24, weight: .heavy)
                        Text("\(state.distanceText) · \(state.direction)").scaledFont(size: 17, weight: .semibold)
                    }
                    Spacer(minLength: 0)
                    Button { state.testPulse() } label: { Image(systemName: "applewatch.radiowaves.left.and.right").font(.system(size: 20, weight: .bold)).frame(width: 54, height: 54).background(.white.opacity(0.18), in: Circle()) }
                        .accessibilityLabel("Test watch notification pulse")
                }.foregroundStyle(.white).padding(17).background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 22)).padding(18)
            }
        }.background(.black).preferredColorScheme(.dark).onDisappear {
            state.restoreBrightness()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

private struct FilledButtonStyle: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaledFont(size: 17, weight: .bold).foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(0.72)
            .background(color.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 17))
    }
}
private struct SoftButtonStyle: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaledFont(size: 16, weight: .bold).foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.72)
            .background(color.opacity(configuration.isPressed ? 0.14 : 0.09), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(color.opacity(0.16), lineWidth: 1))
    }
}

private struct ScaledFontModifier: ViewModifier {
    private let size: CGFloat
    private let weight: Font.Weight
    init(size: CGFloat, weight: Font.Weight) {
        self.size = size
        self.weight = weight
    }
    func body(content: Content) -> some View {
        content.font(.custom(AppTypography.fontName, size: size, relativeTo: .body).weight(weight))
    }
}

private struct DeviceConnectionsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Earbuds for spoken guidance") {
                    Text("Connect Bluetooth earbuds in iPhone Settings → Bluetooth. Drishti sends voice prompts to the iPhone’s active audio output and speaks left, ahead, or right when an obstacle is detected.")
                    AudioOutputPicker().frame(height: 52)
                    Label("Earbud directions use the phone’s audio route. Drishti does not control earbud buttons, ANC, or transparency.", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Huawei Watch Fit 2") {
                    Label("Watch Fit 2 supports iPhone notifications through Huawei Health. Drishti sends an obstacle notification for the watch to mirror; the iPhone handles the rapid haptic alerts.", systemImage: "applewatch")
                    Text("1. Pair the watch in Huawei Health: Devices → Add → Watch → HUAWEI WATCH FIT 2. 2. Allow Bluetooth and notifications when iOS asks. 3. In Huawei Health, open the watch under Devices → Notifications and turn on notification sync; enable Drishti if it appears in the app list.")
                    Button { state.enableNotifications() } label: {
                        Label("Enable Drishti watch alerts", systemImage: "bell.badge")
                    }
                    if let message = state.permissionMessage {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let compatibilityURL = URL(string: "https://consumer.huawei.com/en/support/content/en-us15893442/") {
                        Link("Check Huawei Watch Fit 2 iPhone compatibility", destination: compatibilityURL)
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        Label("Open Drishti notification settings", systemImage: "gearshape")
                    }
                }
                Section("Other watches") {
                    Label("Pair each watch in its own companion app. Apple Watch requires a watchOS companion app for direct Drishti features; this project currently sends iPhone notifications for supported notification mirroring.", systemImage: "applewatch")
                    Text("Notification delivery and vibration depend on the watch, its companion app, iOS permissions, and Bluetooth connection. Drishti cannot universally pair third-party watches or directly control their vibration motors.")
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        Label("Open Drishti notification settings", systemImage: "gearshape")
                    }
                }
                Section("Quick start") {
                    Label("Triple tap the Drishti title inside the app to start obstacle awareness. iOS reserves the phone’s side button for system functions, so apps cannot detect its triple click.", systemImage: "hand.tap")
                }
            }
            .navigationTitle("Devices & audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

private struct AudioOutputPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.prioritizesVideoDevices = false
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}

private extension View {
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight))
    }
}
