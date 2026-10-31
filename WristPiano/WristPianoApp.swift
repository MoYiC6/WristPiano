import SwiftUI

@main
struct WristPianoApp: App {
    @State private var model = PianoModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
    }
}
