import SwiftUI

struct HelpView: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        NavigationStack {
            List {
                Section("Getting started") {
                    Label("Allow camera access for obstacle awareness.", systemImage: "camera")
                    Label("Allow location access while using Drishit to record a trip.", systemImage: "location")
                    Label("Enter a destination and open the walking route in Google Maps.", systemImage: "map")
                    Label("Save your home location before using Take me home.", systemImage: "house")
                }
                Section("Huawei Watch Fit 2") {
                    Text("Drishit cannot directly control the watch vibration motor. In iPhone Settings → Notifications → Drishit, allow notifications. In Huawei Health → Devices → Huawei Watch Fit 2 → Notifications, enable Drishit. Test with Test Pulse. Mirroring and vibration depend on Huawei Health and watch settings.")
                }
                Section("Speech and audio") {
                    Text("Spoken prompts use the current iPhone audio route, including connected earbuds. During a phone or FaceTime call, Drishit pauses speech. If supported by your earbuds, enable transparency mode manually.")
                }
                Section("Privacy and safety") {
                    Text("Route breadcrumbs and saved home stay on this iPhone. Drishit is an assistive prototype, not a certified navigation device. Keep using a cane, guide dog, mobility training, and other support. AR depth varies with device, lighting, motion, and scene texture. iOS may delay or throttle notifications.")
                }
                Section("Camera and screen") {
                    Text("Dim Screen lowers brightness while the camera is running. iOS limits camera and AR work when the app is backgrounded or the screen is locked; keep the phone awake during use.")
                }
                Section("Route path") {
                    Text("Google Maps receives your destination and provides its own walking directions. Drishit records GPS breadcrumbs while the app is active and adds detected obstacle notes when location and depth are available. This version does not provide spoken turn-by-turn instructions inside Drishit.")
                }
            }.navigationTitle("Help & settings").navigationBarTitleDisplayMode(.inline)
        }
        .font(.custom(AppTypography.fontName, size: 17, relativeTo: .body))
    }
}
