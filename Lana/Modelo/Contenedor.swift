import Foundation
import SwiftData
import AppIntents

/// El App Group deja que la app y el widget lean la misma base.
let grupoLana = "group.com.geboou.lana"

/// Contenedor único: lo usan la app, el widget y los App Intents.
enum ContenedorLana {
    static let compartido: ModelContainer = {
        let esquema = Schema([Cuenta.self, Movimiento.self, Categoria.self, Suscripcion.self])
        // SwiftData revienta con un assert (no con un error que se pueda atrapar)
        // si le pides un App Group que no existe, así que preguntamos antes.
        let hayGrupo = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: grupoLana) != nil

        let config = hayGrupo
            ? ModelConfiguration(schema: esquema, groupContainer: .identifier(grupoLana))
            : ModelConfiguration(schema: esquema)

        do {
            return try ModelContainer(for: esquema, configurations: config)
        } catch {
            fatalError("No se pudo abrir la base local: \(error)")
        }
    }()
}

/// Banderas que se pasan entre el widget, los atajos y la app.
enum Señales {
    static let abrirCaptura = Notification.Name("lana.abrirCaptura")
    static let llaveCaptura = "lana.abrirCapturaPendiente"

    /// UserDefaults compartido: el de .standard no cruza al widget.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: grupoLana) ?? .standard
    }
}

/// Preferencias sueltas que no ameritan su propio modelo.
enum Preferencias {
    static let llaveCuentaGastos = "lana.cuentaParaGastos"
    static let llaveUltimaCuenta = "lana.ultimaCuenta"

    /// Con qué cuenta se capturan los gastos por default.
    static var cuentaParaGastos: UUID? {
        get {
            guard let s = Señales.defaults.string(forKey: llaveCuentaGastos) else { return nil }
            return UUID(uuidString: s)
        }
        set { Señales.defaults.set(newValue?.uuidString, forKey: llaveCuentaGastos) }
    }

    /// La última que usaste; solo aplica si no hay una fija configurada.
    static var ultimaCuenta: UUID? {
        get {
            guard let s = Señales.defaults.string(forKey: llaveUltimaCuenta) else { return nil }
            return UUID(uuidString: s)
        }
        set { Señales.defaults.set(newValue?.uuidString, forKey: llaveUltimaCuenta) }
    }

    /// La cuenta con la que debe arrancar una captura nueva.
    static func cuentaInicial(entre cuentas: [Cuenta]) -> Cuenta? {
        if let id = cuentaParaGastos, let fija = cuentas.first(where: { $0.id == id && $0.activa }) {
            return fija
        }
        if let id = ultimaCuenta, let ultima = cuentas.first(where: { $0.id == id && $0.activa }) {
            return ultima
        }
        return cuentas.first(where: \.activa)
    }
}

/// La usan el widget y la automatización de Wallet: abre Lana en la captura.
struct AbrirCapturaIntent: AppIntent {
    static var title: LocalizedStringResource = "Abrir captura rápida"
    static var description = IntentDescription("Abre Lana listo para registrar el gasto que acabas de hacer.")
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        Señales.defaults.set(true, forKey: Señales.llaveCaptura)
        NotificationCenter.default.post(name: Señales.abrirCaptura, object: nil)
        return .result()
    }
}
