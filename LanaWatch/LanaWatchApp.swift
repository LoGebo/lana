import SwiftUI

@main
struct LanaWatchApp: App {
    @StateObject private var modelo = ModeloWatch()
    @StateObject private var entreno = EntrenoModelo()
    var body: some Scene {
        WindowGroup {
            TabView {
                HoyView()
                EntrenoView()
                GastoView()
                PesoView()
            }
            .tabViewStyle(.verticalPage)
            .environmentObject(modelo)
            .environmentObject(entreno)
            .task { await modelo.arrancar() }
        }
    }
}
