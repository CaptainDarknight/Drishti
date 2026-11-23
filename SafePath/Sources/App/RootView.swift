import SwiftUI

enum AppTypography {
    static let fontName = "Inter-Regular"
}

private enum SafePalette {
    static let canvas = Color(red: 0.94, green: 0.96, blue: 0.98)
    static let ink = Color(red: 0.08, green: 0.12, blue: 0.19)
    static let muted = Color(red: 0.36, green: 0.42, blue: 0.49)
    static let blue = Color(red: 0.27, green: 0.34, blue: 0.83)
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
                        Text("Drishit is an assistive tool. Keep using your usual mobility aid.")
                            .font(.custom(AppTypography.fontName, size: 13, relativeTo: .footnote)).foregroundStyle(SafePalette.muted).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 3).accessibilityLabel("Safety reminder. Drishit is an assistive tool. Continue using your usual mobility aid.")
                    }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)
                }
                bottomBar
            }
        }
        .font(.custom(AppTypography.fontName, size: 17, relativeTo: .body))
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingHelp) { HelpView().environmentObject(state) }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: { state.stopCamera() }) { cameraScreen }
        .alert("Enable safety alerts?", isPresented: $showingNotificationIntro) {
            Button("Enable notifications") { state.enableNotifications() }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("Drishit can send obstacle alerts to iPhone notifications. Huawei Health may mirror them to a paired watch when notification access is enabled.")
        }
        .onAppear {
            if !UserDefaults.standard.bool(forKey: "SafePath.notificationIntroShown") {
                UserDefaults.standard.set(true, forKey: "SafePath.notificationIntroShown")
                showingNotificationIntro = true
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { state.appDidEnterBackground() }
            else if showingCamera { state.startCamera() }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                Circle().fill(Color.white).frame(width: 46, height: 46)
                Image(systemName: "figure.walk").font(.system(size: 22, weight: .bold)).foregroundStyle(SafePalette.blue)
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).scaledFont(size: 14, weight: .medium).foregroundStyle(SafePalette.muted)
                Text("Drishit").scaledFont(size: 21, weight: .bold).foregroundStyle(SafePalette.ink)
            }
            Spacer()
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
                    Label("Take me home", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity).frame(minHeight: 60)
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
        }.padding(.horizontal, 15).frame(minHeight: 60).background(SafePalette.canvas, in: RoundedRectangle(cornerRadius: 15))
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
            tabButton("Plan", icon: "sparkles", index: 0)
            tabButton("My walk", icon: "chart.bar.fill", index: 1)
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
        }.background(.black).preferredColorScheme(.dark).onDisappear { state.restoreBrightness() }
    }
}

private struct FilledButtonStyle: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaledFont(size: 17, weight: .bold).foregroundStyle(.white)
            .background(color.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 17))
    }
}
private struct SoftButtonStyle: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaledFont(size: 16, weight: .bold).foregroundStyle(color)
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

private extension View {
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight))
    }
}
