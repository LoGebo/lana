import SwiftUI
import SwiftData

@main
struct LanaApp: App {
    @Environment(\.scenePhase) private var fase
    init() { PuenteWatch.shared.iniciar() }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(ContenedorLana.compartido)
        .onChange(of: fase) { _, _ in PuenteWatch.shared.enviarResumen() }
    }
}
