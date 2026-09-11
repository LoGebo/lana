import Foundation
import SwiftData

/// Depósito automático de la quincena.
///
/// El 15 y el 30 de cada mes (o el último día, si el mes es más corto) entra
/// la mitad del ingreso mensual a la cuenta que escojas. Se revisa cada vez
/// que abres la app, así que si no la abriste el día 15, al abrirla se pone
/// al corriente con la fecha correcta.
enum Nomina {
    static let llaveActiva = "lana.quincena.activa"
    static let llaveCuenta = "lana.quincena.cuenta"
    static let llaveDesde = "lana.quincena.desde"
    static let llaveIngreso = "lana.ingresoMensual"

    /// Marca con la que reconocemos los depósitos que puso la app sola.
    static let marca = "Depósito automático de quincena"

    static var activa: Bool {
        get { Señales.defaults.bool(forKey: llaveActiva) }
        set { Señales.defaults.set(newValue, forKey: llaveActiva) }
    }

    static var ingresoMensual: Double {
        Señales.defaults.double(forKey: llaveIngreso)
    }

    static var quincena: Double { ingresoMensual / 2 }

    static var cuentaID: UUID? {
        get {
            guard let s = Señales.defaults.string(forKey: llaveCuenta) else { return nil }
            return UUID(uuidString: s)
        }
        set { Señales.defaults.set(newValue?.uuidString, forKey: llaveCuenta) }
    }

    /// Desde cuándo empezamos a depositar (se fija al prender el switch,
    /// para no rellenar quincenas de antes de que lo activaras).
    static var desde: Date {
        get { (Señales.defaults.object(forKey: llaveDesde) as? Date) ?? Date() }
        set { Señales.defaults.set(newValue, forKey: llaveDesde) }
    }

    // MARK: - Fechas

    /// Los dos días de pago del mes de esa fecha, a las 9 de la mañana.
    static func fechasDePago(enElMesDe fecha: Date, calendario: Calendar = .current) -> [Date] {
        let partes = calendario.dateComponents([.year, .month], from: fecha)
        guard let inicioMes = calendario.date(from: partes),
              let rango = calendario.range(of: .day, in: .month, for: inicioMes) else { return [] }
        let ultimoDia = rango.count
        return [15, min(30, ultimoDia)].compactMap {
            calendario.date(from: DateComponents(year: partes.year, month: partes.month, day: $0, hour: 9))
        }
    }

    /// Quincenas que ya cayeron y todavía no se han depositado.
    static func pendientes(desde inicio: Date, hasta fin: Date = Date(), calendario: Calendar = .current) -> [Date] {
        var fechas: [Date] = []
        var cursor = calendario.date(from: calendario.dateComponents([.year, .month], from: inicio)) ?? inicio
        while cursor <= fin {
            for f in fechasDePago(enElMesDe: cursor) where f > inicio && f <= fin {
                fechas.append(f)
            }
            guard let siguiente = calendario.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = siguiente
        }
        return fechas.sorted()
    }

    static func siguientePago(despuesDe fecha: Date = Date(), calendario: Calendar = .current) -> Date? {
        for f in fechasDePago(enElMesDe: fecha) where f > fecha { return f }
        guard let siguienteMes = calendario.date(byAdding: .month, value: 1, to: fecha) else { return nil }
        return fechasDePago(enElMesDe: siguienteMes).first
    }

    // MARK: - Depósito

    static func cuenta(entre cuentas: [Cuenta]) -> Cuenta? {
        if let id = cuentaID, let elegida = cuentas.first(where: { $0.id == id }) {
            return elegida
        }
        // Por default cae en BBVA; si no existe, la primera de débito.
        return cuentas.first { $0.activa && $0.nombre.localizedCaseInsensitiveContains("bbva") }
            ?? cuentas.first { $0.activa && $0.tipo == .debito }
            ?? cuentas.first(where: \.activa)
    }

    /// Crea los movimientos de las quincenas que hayan caído. Es idempotente:
    /// si ya existe el depósito de ese día, no lo duplica.
    @MainActor
    @discardableResult
    static func depositarPendientes(_ contexto: ModelContext) -> Int {
        guard activa, quincena > 0 else { return 0 }

        // No rellenamos más de 3 meses hacia atrás.
        let piso = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? desde
        let inicio = max(desde, piso)

        let fechas = pendientes(desde: inicio)
        guard !fechas.isEmpty else { return 0 }

        let cuentas = (try? contexto.fetch(FetchDescriptor<Cuenta>())) ?? []
        let categorias = (try? contexto.fetch(FetchDescriptor<Categoria>())) ?? []
        let movimientos = (try? contexto.fetch(FetchDescriptor<Movimiento>())) ?? []

        let destino = cuenta(entre: cuentas)
        let sueldo = categorias.first { $0.esIngreso && $0.nombre == "Sueldo" }
            ?? categorias.first { $0.esIngreso }

        let calendario = Calendar.current
        var creados = 0
        for fecha in fechas {
            let yaExiste = movimientos.contains {
                $0.nota == marca && calendario.isDate($0.fecha, inSameDayAs: fecha)
            }
            guard !yaExiste else { continue }

            contexto.insert(Movimiento(
                monto: quincena,
                fecha: fecha,
                tipo: .ingreso,
                comercio: "Quincena",
                nota: marca,
                cuenta: destino,
                categoria: sueldo
            ))
            creados += 1
        }

        desde = Date()
        if creados > 0 { try? contexto.save() }
        return creados
    }
}
