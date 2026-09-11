import AppIntents
import SwiftData
import Foundation

// MARK: - Categoría como entidad (para poder decirla en la frase de Siri)

struct CategoriaEntidad: AppEntity {
    let id: String
    let nombre: String
    let emoji: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Categoría"
    static var defaultQuery = ConsultaCategorias()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji) \(nombre)")
    }
}

struct ConsultaCategorias: EntityStringQuery {
    @MainActor
    private func todas() -> [Categoria] {
        let contexto = ContenedorLana.compartido.mainContext
        let categorias = (try? contexto.fetch(FetchDescriptor<Categoria>())) ?? []
        return categorias.sorted { $0.orden < $1.orden }
    }

    private func entidad(_ c: Categoria) -> CategoriaEntidad {
        CategoriaEntidad(id: c.id.uuidString, nombre: c.nombre, emoji: c.emoji)
    }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [CategoriaEntidad] {
        todas().filter { identifiers.contains($0.id.uuidString) }.map(entidad)
    }

    /// Lo que dijiste no tiene que ser el nombre exacto: "oxxo" cae en Antojos.
    @MainActor
    func entities(matching string: String) async throws -> [CategoriaEntidad] {
        let categorias = todas()
        if let encontrada = Adivinador.buscar(string, en: categorias) {
            return [entidad(encontrada)]
        }
        return categorias
            .filter { $0.nombre.localizedCaseInsensitiveContains(string) }
            .map(entidad)
    }

    @MainActor
    func suggestedEntities() async throws -> [CategoriaEntidad] {
        todas().filter { !$0.esIngreso }.map(entidad)
    }
}

struct OpcionesCuenta: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [String] {
        let contexto = ContenedorLana.compartido.mainContext
        let cuentas = (try? contexto.fetch(FetchDescriptor<Cuenta>())) ?? []
        return cuentas.filter(\.activa).sorted { $0.orden < $1.orden }.map(\.nombre)
    }
}

// MARK: - Registrar gasto

struct RegistrarGastoIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar gasto"
    static var description = IntentDescription("Guarda un gasto en Lana sin abrir la app.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Monto", requestValueDialog: "¿De cuánto fue?")
    var monto: Double

    @Parameter(title: "Categoría")
    var categoria: CategoriaEntidad?

    @Parameter(title: "Dónde", default: "")
    var comercio: String

    @Parameter(title: "Cuenta", optionsProvider: OpcionesCuenta())
    var cuenta: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$monto) en \(\.$categoria)") {
            \.$comercio
            \.$cuenta
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let contexto = ContenedorLana.compartido.mainContext
        let categorias = (try? contexto.fetch(FetchDescriptor<Categoria>())) ?? []
        let cuentas = (try? contexto.fetch(FetchDescriptor<Cuenta>())) ?? []

        // 1) La categoría que dijiste en la frase.
        var elegida: Categoria? = {
            if let id = categoria?.id, let uuid = UUID(uuidString: id) {
                return categorias.first { $0.id == uuid }
            }
            return nil
        }()

        // 2) Si no, la deducimos de dónde gastaste ("OXXO" → Antojos).
        var donde = comercio.trimmingCharacters(in: .whitespaces)
        if elegida == nil, !donde.isEmpty {
            elegida = Adivinador.buscar(donde, en: categorias)
        }

        // 3) Si seguimos sin saber, Siri lo pregunta.
        if elegida == nil {
            let respuesta = try await $comercio.requestValue(IntentDialog("¿En qué te lo gastaste?"))
            donde = respuesta.trimmingCharacters(in: .whitespaces)
            elegida = Adivinador.buscar(donde, en: categorias)
        }

        let cta: Cuenta? = {
            if let nombre = cuenta,
               let encontrada = cuentas.first(where: { $0.nombre.localizedCaseInsensitiveCompare(nombre) == .orderedSame }) {
                return encontrada
            }
            return Preferencias.cuentaInicial(entre: cuentas)
        }()

        let movimiento = Movimiento(
            monto: monto,
            tipo: .gasto,
            comercio: donde,
            cuenta: cta,
            categoria: elegida,
            creadoPorAtajo: true
        )
        contexto.insert(movimiento)
        try? contexto.save()

        let detalle = elegida.map { " en \($0.nombre)" } ?? (donde.isEmpty ? "" : " en \(donde)")
        return .result(dialog: IntentDialog("Listo, anoté \(pesos(monto, decimales: false))\(detalle)."))
    }
}

// MARK: - Consulta rápida

struct GastoDelMesIntent: AppIntent {
    static var title: LocalizedStringResource = "Cuánto llevo gastado"
    static var description = IntentDescription("Te dice cuánto llevas gastado en el mes.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let contexto = ContenedorLana.compartido.mainContext
        let movimientos = (try? contexto.fetch(FetchDescriptor<Movimiento>())) ?? []
        let delMes = Finanzas.movimientos(movimientos, en: Finanzas.rangoDelMes(de: Date()))
        let total = Finanzas.totalGastos(delMes)
        return .result(dialog: IntentDialog("Llevas \(pesos(total, decimales: false)) gastados este mes."))
    }
}

struct MiLanaIntent: AppIntent {
    static var title: LocalizedStringResource = "Cuánto tengo"
    static var description = IntentDescription("Tu patrimonio y lo que están generando tus inversiones.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let contexto = ContenedorLana.compartido.mainContext
        let movimientos = (try? contexto.fetch(FetchDescriptor<Movimiento>())) ?? []
        let cuentas = (try? contexto.fetch(FetchDescriptor<Cuenta>())) ?? []
        let total = Finanzas.patrimonio(cuentas: cuentas, movimientos: movimientos)
        let hoy = Finanzas.rendimientoDeHoy(cuentas: cuentas, movimientos: movimientos)
        return .result(dialog: IntentDialog(
            "Tienes \(pesos(total, decimales: false)) y hoy estás generando \(pesos(hoy)) de rendimiento."
        ))
    }
}

// MARK: - Frases

struct AtajosLana: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RegistrarGastoIntent(),
            phrases: [
                "Registra un gasto en \(.applicationName)",
                "Registra un gasto de \(\.$categoria) en \(.applicationName)",
                "Anota un gasto en \(.applicationName)",
                "Anota un gasto de \(\.$categoria) en \(.applicationName)",
                "Apunta un gasto en \(.applicationName)",
                "Nuevo gasto en \(.applicationName)",
                "Gasté en \(.applicationName)",
                "Agrega un gasto de \(\.$categoria) en \(.applicationName)",
                "Gasté en \(\.$categoria) en \(.applicationName)",
                "Registra \(\.$categoria) en \(.applicationName)",
                "Apunta \(\.$categoria) en \(.applicationName)"
            ],
            shortTitle: "Registrar gasto",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: AbrirCapturaIntent(),
            phrases: [
                "Abre la captura de \(.applicationName)",
                "Captura en \(.applicationName)",
                "Abre \(.applicationName) para registrar"
            ],
            shortTitle: "Captura rápida",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: GastoDelMesIntent(),
            phrases: [
                "Cuánto llevo gastado en \(.applicationName)",
                "Cuánto he gastado en \(.applicationName)",
                "Mis gastos del mes en \(.applicationName)"
            ],
            shortTitle: "Gasto del mes",
            systemImageName: "chart.pie.fill"
        )
        AppShortcut(
            intent: MiLanaIntent(),
            phrases: [
                "Cuánto tengo en \(.applicationName)",
                "Cuánta lana tengo en \(.applicationName)",
                "Mi patrimonio en \(.applicationName)"
            ],
            shortTitle: "Cuánto tengo",
            systemImageName: "wallet.bifold.fill"
        )
    }
}
