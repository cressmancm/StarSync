import SwiftUI

@main
struct StarSyncApp: App {
    var body: some Scene {
        Window("StarSync", id: "main") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
