import SwiftUI
import SwiftData
import AppIntents

struct ContentView: View {
    @Environment(\.modelContext) private var contexto
    @Environment(\.scenePhase) private var faseDeEscena
    @State private var pestaña = 6
    @State private var mostrandoCaptura = false
    @State private var fechaCaptura: Date?

    var body: some View {
        TabView(selection: $pestaña) {
            PanelView(irA: { pestaña = $0 }, capturar: { fechaCaptura = nil; mostrandoCaptura = true })
                .tabItem { Label("Panel", systemImage: "square.grid.2x2.fill") }
                .tag(6)

            ResumenView(mostrandoCaptura: $mostrandoCaptura, fechaCaptura: $fechaCaptura)
                .tabItem { Label("Resumen", systemImage: "chart.pie.fill") }
                .tag(0)

            MovimientosView(mostrandoCaptura: $mostrandoCaptura)
                .tabItem { Label("Movimientos", systemImage: "list.bullet") }
                .tag(1)

            ProtocolosRaiz()
                .tabItem { Label("Protocolos", systemImage: "checklist") }
                .tag(5)

            CuentasView()
                .tabItem { Label("Cuentas", systemImage: "wallet.bifold.fill") }
                .tag(2)

            PresupuestoView()
                .tabItem { Label("Presupuesto", systemImage: "chart.bar.doc.horizontal") }
                .tag(3)

            AjustesView()
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
                .tag(4)

        }
        .tint(.green)
        .task {
            Semillas.sembrarSiHaceFalta(contexto)
            Semillas.aplicarColoresDeMarca(contexto)
            Semillas.asegurarCategorias(contexto)
            Semillas.separarTarjetaNu(contexto)
            Semillas.aplicarPersonalizacion(contexto)
            AtajosLana.updateAppShortcutParameters()
            Semillas.sembrarDemoSiSePide(contexto)
            Nomina.depositarPendientes(contexto)
            revisarCapturaPendiente()
            await SincronizadorAgente.sincronizar(finanzas: contexto, protocolos: ContenedorProtocolos.compartido.mainContext)
        }
        .onChange(of: faseDeEscena) { _, f in
            if f == .active { Task { await SincronizadorAgente.sincronizar(finanzas: contexto, protocolos: ContenedorProtocolos.compartido.mainContext) } }
        }
        .sheet(isPresented: $mostrandoCaptura) {
            EditorMovimientoView(fechaInicial: fechaCaptura)
        }
        .onChange(of: mostrandoCaptura) { _, abierta in if !abierta { fechaCaptura = nil } }
        .onReceive(NotificationCenter.default.publisher(for: Señales.abrirCaptura)) { _ in
            mostrandoCaptura = true
        }
        .onChange(of: faseDeEscena) { _, fase in
            // Si la app se quedó abierta y cayó una quincena, la registra al volver.
            if fase == .active { Nomina.depositarPendientes(contexto) }
        }
    }

    /// El atajo de Wallet deja una bandera; al abrir la app saltamos a capturar.
    private func revisarCapturaPendiente() {
        if Señales.defaults.bool(forKey: Señales.llaveCaptura) {
            Señales.defaults.set(false, forKey: Señales.llaveCaptura)
            mostrandoCaptura = true
        }
    }
}
