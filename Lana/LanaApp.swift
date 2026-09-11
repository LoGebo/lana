import SwiftUI
import SwiftData

@main
struct LanaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(ContenedorLana.compartido)
    }
}
