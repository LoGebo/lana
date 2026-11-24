import SwiftUI
import SwiftData

enum SeccionProtocolos: String, CaseIterable, Identifiable {
    case hoy, gym, comida, sueno
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .hoy: "Hoy"
        case .gym: "Gym"
        case .comida: "Comida"
        case .sueno: "Sueño"
        }
    }
}

/// Único punto de entrada de Protocolos. Trae su propia base de datos,
/// separada de la de finanzas.
struct ProtocolosRaiz: View {
    var body: some View {
        NavigationStack { ContenidoProtocolos() }
            .modelContainer(ContenedorProtocolos.compartido)
    }
}

private struct ContenidoProtocolos: View {
    @Environment(\.modelContext) private var contexto
    @AppStorage("protocolos.seccion") private var seccionRaw = "hoy"
    private var seccion: Binding<SeccionProtocolos> {
        Binding(get: { SeccionProtocolos(rawValue: seccionRaw) ?? .hoy }, set: { seccionRaw = $0.rawValue })
    }
    @StateObject private var salud = SaludService()
    @Environment(\.scenePhase) private var escena

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sección", selection: seccion) {
                ForEach(SeccionProtocolos.allCases) { Text($0.nombre).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            switch seccion.wrappedValue {
            case .hoy: HoyView(salud: salud)
            case .gym: GymView()
            case .comida: ComidaView()
            case .sueno: SuenoView(salud: salud)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            Biblioteca.sembrarSiHaceFalta(contexto)
            await salud.sincronizar(contexto)
        }
        .onChange(of: escena) { _, nueva in if nueva == .active { Task { await salud.sincronizar(contexto) } } }
    }
}
