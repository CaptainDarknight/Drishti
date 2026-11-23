import SwiftUI

struct HelpView: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        NavigationStack {
            List {
                Section("Getting started") {
                    Label("Allow camera access for obstacle awareness.", systemImage: "camera")
                    Label("Allow location access while using Drishti to record a trip.", systemImage: "location")
                    Label("Allow Motion & Fitness access to show step totals.", systemImage: "figure.walk")
                    Label("Enter a destination and open the walking route in Google Maps.", systemImage: "map")
                    Label("Save your home location before using Take me home.", systemImage: "house")
                }
                Section("Huawei Watch Fit 2") {
                    Text("The Fit 2 supports iPhone notifications through Huawei Health. Pair it in Huawei Health → Devices → Add → Watch, then enable notification sync in the Fit 2 device settings and allow Drishti in iPhone notifications. Drishti sends watch-mirrorable obstacle alerts and strong iPhone haptics; iOS does not let Drishti directly control the Fit 2 vibration motor. Test pulse checks notification access.")
                }
                Section("Speech and audio") {
                    Text("Spoken prompts use the current iPhone audio route, including connected earbuds. During a phone or FaceTime call, Drishti pauses speech. If supported by your earbuds, enable transparency mode manually.")
                }
                Section("Privacy and safety") {
                    Text("Route breadcrumbs and saved home stay on this iPhone. Drishti is an assistive prototype, not a certified navigation device. Keep using a cane, guide dog, mobility training, and other support. Vision can miss or mislabel objects; the SE 2 may not provide reliable distance estimates. iOS may delay or throttle watch notifications.")
                }
                Section("Camera and screen") {
                    Text("Obstacle awareness uses the rear camera while the full-screen camera view is open. iOS pauses camera analysis when Drishti is backgrounded; GPS route recording can continue with Always location access. Keep the phone unlocked while using obstacle awareness.")
                }
                Section("Route path") {
                    Text("Google Maps receives your destination and provides its own walking directions. Drishti records GPS breadcrumbs while location access is available and adds detected obstacle notes. Obstacle voice cues can say left, ahead, or right. Drishti does not provide live turn-by-turn route instructions.")
                }
            }.navigationTitle("Help & settings").navigationBarTitleDisplayMode(.inline)
        }
        .font(.custom(AppTypography.fontName, size: 17, relativeTo: .body))
    }
}
