import SwiftUI

@main
struct SafePathApp: App {
    @StateObject private var state = AppState()
    var body: some Scene { WindowGroup { RootView().environmentObject(state) } }
}
