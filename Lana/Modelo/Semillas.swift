import Foundation
import SwiftData

/// Datos iniciales para no arrancar con una pantalla vacía.
enum Semillas {

    @MainActor
    static func sembrarSiHaceFalta(_ contexto: ModelContext) {
        let categorias = (try? contexto.fetch(FetchDescriptor<Categoria>())) ?? []
        if categorias.isEmpty { sembrarCategorias(contexto) }

        let cuentas = (try? contexto.fetch(FetchDescriptor<Cuenta>())) ?? []
        if cuentas.isEmpty { sembrarCuentas(contexto) }

        try? contexto.save()
    }

    private static func sembrarCategorias(_ contexto: ModelContext) {
        let gastos: [(String, String, String)] = [
            ("Comida fuera", "🍔", "#FF9F0A"),
            ("Súper", "🛒", "#30D158"),
            ("Antojos / OXXO", "🍺", "#FFD60A"),
            ("Transporte", "🚗", "#0A84FF"),
            ("Suscripciones", "📺", "#BF5AF2"),
            ("Gym", "🏋️", "#FF375F"),
            ("Casa / Renta", "🏠", "#AC8E68"),
            ("Servicios", "💡", "#64D2FF"),
            ("Salud", "💊", "#FF6482"),
            ("Ropa", "👕", "#5E5CE6"),
            ("Diversión", "🎬", "#40C8E0"),
            ("Viajes", "✈️", "#0A84FF"),
            ("Regalos", "🎁", "#FF375F"),
            ("Pendejadas", "🤷", "#8E8E93")
        ]
        for (i, c) in gastos.enumerated() {
            contexto.insert(Categoria(nombre: c.0, emoji: c.1, colorHex: c.2, orden: i))
        }

        let ingresos: [(String, String, String)] = [
            ("Sueldo", "💼", "#30D158"),
            ("Rendimientos", "📈", "#64D2FF"),
            ("Otros ingresos", "➕", "#8E8E93")
        ]
        for (i, c) in ingresos.enumerated() {
            contexto.insert(Categoria(nombre: c.0, emoji: c.1, colorHex: c.2, esIngreso: true, orden: 100 + i))
        }
    }

    private static func sembrarCuentas(_ contexto: ModelContext) {
        let base: [(String, String, TipoCuenta, String)] = [
            ("Efectivo", "", .efectivo, "#30D158"),
            ("BBVA", "BBVA", .debito, "#0A84FF"),
            ("Nu", "Nu", .credito, "#BF5AF2"),
            ("Plata", "Plata Card", .credito, "#8E8E93"),
            ("Mercado Pago", "Mercado Pago", .inversion, "#64D2FF"),
            ("Revolut", "Revolut", .inversion, "#5E5CE6"),
            ("DiDi Finanzas", "DiDi", .inversion, "#FF9F0A")
        ]
        for (i, c) in base.enumerated() {
            contexto.insert(Cuenta(nombre: c.0, institucion: c.1, tipo: c.2, colorHex: c.3, orden: i))
        }
    }
}


// MARK: - Datos de ejemplo (solo para probar, se activa con LANA_DEMO=1)

extension Semillas {
    @MainActor
    static func sembrarDemoSiSePide(_ contexto: ModelContext) {
        guard ProcessInfo.processInfo.environment["LANA_DEMO"] == "1" else { return }
        let existentes = (try? contexto.fetch(FetchDescriptor<Movimiento>())) ?? []
        guard existentes.isEmpty else { return }

        let categorias = (try? contexto.fetch(FetchDescriptor<Categoria>())) ?? []
        let cuentas = (try? contexto.fetch(FetchDescriptor<Cuenta>())) ?? []
        func cat(_ n: String) -> Categoria? { categorias.first { $0.nombre == n } }
        func cta(_ n: String) -> Cuenta? { cuentas.first { $0.nombre == n } }

        for c in cuentas {
            switch c.nombre {
            case "BBVA": c.saldoInicial = 18_400
            case "Efectivo": c.saldoInicial = 1_200
            default: break
            }
            // Para poder ver el rendimiento acumulado sin esperar un mes.
            if c.rendimientoAnual > 0 {
                c.fechaBase = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            }
        }

        let muestras: [(Int, Double, String, String, String)] = [
            (0, 189, "Comida fuera", "BBVA", "Sushi Roll"),
            (0, 62, "Antojos / OXXO", "Efectivo", "7-Eleven"),
            (1, 1_240, "Súper", "BBVA", "Chedraui"),
            (1, 98, "Transporte", "Nu", "Uber"),
            (2, 320, "Comida fuera", "Nu", "Tacos El Güero"),
            (3, 899, "Gym", "BBVA", "Smart Fit anual"),
            (3, 45, "Antojos / OXXO", "Efectivo", "OXXO"),
            (4, 279, "Suscripciones", "Nu", "Netflix"),
            (5, 1_580, "Casa / Renta", "BBVA", "Luz CFE"),
            (6, 210, "Transporte", "Nu", "Gasolina"),
            (7, 156, "Comida fuera", "BBVA", "Starbucks"),
            (8, 2_400, "Ropa", "Nu", "Zara"),
            (9, 88, "Antojos / OXXO", "Efectivo", "7-Eleven"),
            (10, 640, "Diversión", "BBVA", "Cinepolis"),
            (12, 12_000, "Casa / Renta", "BBVA", "Renta"),
            (14, 430, "Salud", "Nu", "Farmacia")
        ]

        for (dias, monto, categoria, cuenta, comercio) in muestras {
            let fecha = Calendar.current.date(byAdding: .day, value: -dias, to: Date()) ?? Date()
            contexto.insert(Movimiento(monto: monto, fecha: fecha, tipo: .gasto,
                                       comercio: comercio, cuenta: cta(cuenta), categoria: cat(categoria)))
        }

        contexto.insert(Movimiento(monto: 32_000, fecha: Calendar.current.date(byAdding: .day, value: -9, to: Date()) ?? Date(),
                                   tipo: .ingreso, comercio: "Nómina", cuenta: cta("BBVA"), categoria: cat("Sueldo")))

        let subs: [(String, Double, CicloCobro, Int)] = [
            ("Netflix", 279, .mensual, 4),
            ("Spotify", 129, .mensual, 11),
            ("iCloud 2TB", 199, .mensual, 2),
            ("Smart Fit", 4_800, .anual, 45),
            ("ChatGPT Plus", 420, .mensual, 18)
        ]
        for (nombre, monto, ciclo, dias) in subs {
            let fecha = Calendar.current.date(byAdding: .day, value: dias, to: Date()) ?? Date()
            contexto.insert(Suscripcion(nombre: nombre, monto: monto, ciclo: ciclo, proximoCobro: fecha,
                                        cuentaID: cta("Nu")?.id, categoria: cat("Suscripciones")))
        }

        // Quincena activada hace 45 días, para ver los depósitos ya puestos.
        Señales.defaults.set(true, forKey: Nomina.llaveActiva)
        Señales.defaults.set(Calendar.current.date(byAdding: .day, value: -45, to: Date()),
                             forKey: Nomina.llaveDesde)

        // Presupuestos e ingreso de ejemplo.
        Señales.defaults.set(32_000.0, forKey: "lana.ingresoMensual")
        Señales.defaults.set(5_000.0, forKey: "lana.metaAhorro")
        let topes: [String: Double] = [
            "Comida fuera": 2_500, "Súper": 3_000, "Antojos / OXXO": 800,
            "Transporte": 1_500, "Gym": 900, "Casa / Renta": 12_000,
            "Diversión": 1_200, "Novia": 2_000, "Box": 700
        ]
        for c in categorias where topes[c.nombre] != nil {
            c.presupuestoMensual = topes[c.nombre]!
        }

        try? contexto.save()
    }
}

// MARK: - Ajustes de arranque

extension Semillas {
    /// Se asegura de que existan las categorías que hemos ido agregando.
    ///
    /// Sin bandera a propósito: corre en cada arranque y solo inserta las que
    /// falten. Así nadie se queda sin una categoría por un flag mal puesto.
    @MainActor
    static func asegurarCategorias(_ contexto: ModelContext) {
        func normaliza(_ t: String) -> String {
            t.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
                .lowercased()
                .trimmingCharacters(in: .whitespaces)
        }

        let existentes = (try? contexto.fetch(FetchDescriptor<Categoria>())) ?? []
        let nombres = Set(existentes.map { normaliza($0.nombre) })

        let base: [(String, String, String)] = [
            ("Box", "🥊", "#FF375F"),
            ("Novia", "💕", "#FF6482"),
            ("Compras", "🛍️", "#5E5CE6")
        ]

        var agregadas = false
        for (i, c) in base.enumerated() where !nombres.contains(normaliza(c.0)) {
            contexto.insert(Categoria(nombre: c.0, emoji: c.1, colorHex: c.2, orden: 20 + i))
            agregadas = true
        }
        if agregadas { try? contexto.save() }
    }

    /// Separa la tarjeta de crédito Nu de la cuenta Nu que genera rendimiento,
    /// y deja la tarjeta como la cuenta por defecto para capturar gastos.
    ///
    /// Son dos productos distintos: en la cuenta tienes lana rindiendo, y con
    /// la tarjeta generas deuda. Mezclarlas haría que cada compra te bajara
    /// los ahorros, que no es lo que pasa en la realidad.
    @MainActor
    static func separarTarjetaNu(_ contexto: ModelContext) {
        let llave = "lana.tarjetaNu.v1"
        guard !Señales.defaults.bool(forKey: llave) else { return }

        var cuentas = (try? contexto.fetch(FetchDescriptor<Cuenta>())) ?? []

        // Si ya hay una tarjeta de crédito Nu, la respetamos.
        var tarjeta = cuentas.first {
            $0.tipo == .credito && $0.nombre.localizedCaseInsensitiveContains("nu")
        }

        if tarjeta == nil {
            let nueva = Cuenta(nombre: "Nu Tarjeta", institucion: "Nu", tipo: .credito,
                               saldoInicial: 0, rendimientoAnual: 0, colorHex: "#820AD1", orden: 3)
            nueva.notas = "Tarjeta de crédito. El saldo en negativo es lo que debes."
            contexto.insert(nueva)
            cuentas.append(nueva)
            tarjeta = nueva
        }

        // La cuenta de ahorro se llama distinto para no confundirlas.
        if let ahorro = cuentas.first(where: {
            $0.nombre.caseInsensitiveCompare("Nu") == .orderedSame && $0.tipo != .credito
        }) {
            ahorro.nombre = "Nu Cuenta"
        }

        Preferencias.cuentaParaGastos = tarjeta?.id
        Señales.defaults.set(true, forKey: llave)
        try? contexto.save()
    }

    /// Pinta cada cuenta con el color de su banco. Una sola vez, para no
    /// pisar un color que el usuario haya escogido después.
    @MainActor
    static func aplicarColoresDeMarca(_ contexto: ModelContext) {
        let llave = "lana.coloresMarca.v1"
        guard !Señales.defaults.bool(forKey: llave) else { return }

        let cuentas = (try? contexto.fetch(FetchDescriptor<Cuenta>())) ?? []
        for cuenta in cuentas {
            cuenta.colorHex = Marcas.color(para: cuenta.nombre,
                                           institucion: cuenta.institucion,
                                           respaldo: cuenta.colorHex)
        }

        Señales.defaults.set(true, forKey: llave)
        try? contexto.save()
    }
}
