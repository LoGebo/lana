import Foundation

/// Todos los cálculos de lana viven aquí, sin UI, para poder confiar en ellos.
enum Finanzas {

    // MARK: - Saldos

    /// Cuánto mueve un movimiento en esta cuenta (+ entra, − sale).
    private static func efecto(de m: Movimiento, en cuenta: Cuenta) -> Double {
        var delta = 0.0
        if m.cuenta?.id == cuenta.id {
            switch m.tipo {
            case .gasto, .transferencia: delta -= m.monto
            case .ingreso: delta += m.monto
            }
        }
        if m.tipo == .transferencia, m.cuentaDestinoID == cuenta.id {
            delta += m.monto
        }
        return delta
    }

    /// Saldo sin contar rendimientos: lo que tenías ± lo que registraste.
    static func saldoBase(de cuenta: Cuenta, movimientos: [Movimiento]) -> Double {
        movimientos.reduce(cuenta.saldoInicial) { $0 + efecto(de: $1, en: cuenta) }
    }

    /// Saldo real al día de hoy, con el rendimiento que se ha ido generando.
    ///
    /// Simula día por día desde `fechaBase`: aplica los movimientos de cada
    /// día y capitaliza al cierre, que es como funcionan Nu, Mercado Pago,
    /// DiDi y compañía (rendimiento diario que se reinvierte).
    static func saldo(de cuenta: Cuenta, movimientos: [Movimiento], al dia: Date = Date()) -> Double {
        let calendario = Calendar.current
        let inicio = calendario.startOfDay(for: cuenta.fechaBase)
        let hoy = calendario.startOfDay(for: dia)

        let genera = cuenta.acumulaRendimiento && cuenta.rendimientoAnual > 0
        guard genera, hoy > inicio else { return saldoBase(de: cuenta, movimientos: movimientos) }

        // Los movimientos anteriores a la fecha base ya afectan el saldo de
        // arranque; los demás se aplican el día que les toca.
        var saldo = cuenta.saldoInicial
        var porDia: [Date: Double] = [:]
        for m in movimientos {
            let delta = efecto(de: m, en: cuenta)
            guard delta != 0 else { continue }
            let d = calendario.startOfDay(for: m.fecha)
            if d < inicio {
                saldo += delta
            } else {
                porDia[d, default: 0] += delta
            }
        }

        let tasaDiaria = cuenta.rendimientoAnual / 100 / 365
        var cursor = inicio
        while cursor < hoy {
            saldo += porDia[cursor] ?? 0
            if saldo > 0 { saldo *= (1 + tasaDiaria) }
            guard let siguiente = calendario.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = siguiente
        }
        saldo += porDia[hoy] ?? 0
        return saldo
    }

    /// Lo que la cuenta ha generado sola desde que pusiste su saldo.
    static func rendimientoGenerado(de cuenta: Cuenta, movimientos: [Movimiento], al dia: Date = Date()) -> Double {
        saldo(de: cuenta, movimientos: movimientos, al: dia) - saldoBase(de: cuenta, movimientos: movimientos)
    }

    /// Lo que generan hoy todas las cuentas juntas (lo que se suma al cierre).
    static func rendimientoDeHoy(cuentas: [Cuenta], movimientos: [Movimiento]) -> Double {
        cuentas.filter { $0.activa && $0.acumulaRendimiento && $0.rendimientoAnual > 0 }
            .reduce(0.0) { total, cuenta in
                let s = max(0, saldo(de: cuenta, movimientos: movimientos))
                return total + s * (cuenta.rendimientoAnual / 100 / 365)
            }
    }

    static func rendimientoAcumulado(cuentas: [Cuenta], movimientos: [Movimiento]) -> Double {
        cuentas.filter(\.activa).reduce(0.0) { $0 + rendimientoGenerado(de: $1, movimientos: movimientos) }
    }

    /// Desde cuándo lleva corriendo el rendimiento más viejo.
    static func inicioDelRendimiento(cuentas: [Cuenta]) -> Date? {
        cuentas.filter { $0.activa && $0.rendimientoAnual > 0 && $0.acumulaRendimiento }
            .map(\.fechaBase).min()
    }

    /// Lo que realmente tienes: efectivo + débito + inversiones − deuda de tarjetas.
    static func patrimonio(cuentas: [Cuenta], movimientos: [Movimiento]) -> Double {
        cuentas.filter(\.activa).reduce(0) { $0 + saldo(de: $1, movimientos: movimientos) }
    }

    // MARK: - Rangos de fecha

    static func rangoDelMes(de fecha: Date, calendario: Calendar = .current) -> ClosedRange<Date> {
        let inicio = calendario.date(from: calendario.dateComponents([.year, .month], from: fecha)) ?? fecha
        let fin = calendario.date(byAdding: DateComponents(month: 1, second: -1), to: inicio) ?? fecha
        return inicio...fin
    }

    static func movimientos(_ movimientos: [Movimiento], en rango: ClosedRange<Date>) -> [Movimiento] {
        movimientos.filter { rango.contains($0.fecha) }
    }

    // MARK: - Gastos

    /// Las transferencias no cuentan como gasto: solo mueves tu lana de bolsa.
    static func totalGastos(_ movimientos: [Movimiento]) -> Double {
        movimientos.filter { $0.tipo == .gasto }.reduce(0) { $0 + $1.monto }
    }

    static func totalIngresos(_ movimientos: [Movimiento]) -> Double {
        movimientos.filter { $0.tipo == .ingreso }.reduce(0) { $0 + $1.monto }
    }

    struct GastoPorCategoria: Identifiable {
        var id: UUID { categoria?.id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")! }
        let categoria: Categoria?
        let total: Double
        var nombre: String { categoria?.nombre ?? "Sin categoría" }
        var emoji: String { categoria?.emoji ?? "❓" }
        var colorHex: String { categoria?.colorHex ?? "#8E8E93" }
    }

    static func gastosPorCategoria(_ movimientos: [Movimiento]) -> [GastoPorCategoria] {
        let gastos = movimientos.filter { $0.tipo == .gasto }
        var acumulado: [UUID?: (Categoria?, Double)] = [:]
        for g in gastos {
            let llave = g.categoria?.id
            let previo = acumulado[llave]?.1 ?? 0
            acumulado[llave] = (g.categoria, previo + g.monto)
        }
        return acumulado.values
            .map { GastoPorCategoria(categoria: $0.0, total: $0.1) }
            .sorted { $0.total > $1.total }
    }

    struct GastoPorComercio: Identifiable {
        var id: String { comercio }
        let comercio: String
        let total: Double
        let veces: Int
    }

    static func gastosPorComercio(_ movimientos: [Movimiento]) -> [GastoPorComercio] {
        let gastos = movimientos.filter { $0.tipo == .gasto && !$0.comercio.isEmpty }
        var acumulado: [String: (Double, Int)] = [:]
        for g in gastos {
            let llave = g.comercio.trimmingCharacters(in: .whitespaces)
            let previo = acumulado[llave] ?? (0, 0)
            acumulado[llave] = (previo.0 + g.monto, previo.1 + 1)
        }
        return acumulado
            .map { GastoPorComercio(comercio: $0.key, total: $0.value.0, veces: $0.value.1) }
            .sorted { $0.total > $1.total }
    }

    struct GastoDelDia: Identifiable {
        var id: Date { dia }
        let dia: Date
        let total: Double
    }

    static func gastosPorDia(_ movimientos: [Movimiento], calendario: Calendar = .current) -> [GastoDelDia] {
        let gastos = movimientos.filter { $0.tipo == .gasto }
        var acumulado: [Date: Double] = [:]
        for g in gastos {
            let dia = calendario.startOfDay(for: g.fecha)
            acumulado[dia, default: 0] += g.monto
        }
        return acumulado.map { GastoDelDia(dia: $0.key, total: $0.value) }.sorted { $0.dia < $1.dia }
    }

    // MARK: - Inversiones

    /// Tasa anual promedio ponderada por cuánto tienes en cada cuenta.
    static func tasaPonderada(cuentas: [Cuenta], movimientos: [Movimiento]) -> Double {
        let inversiones = cuentas.filter { $0.activa && $0.rendimientoAnual > 0 }
        let total = inversiones.reduce(0.0) { $0 + max(0, saldo(de: $1, movimientos: movimientos)) }
        guard total > 0 else { return 0 }
        let suma = inversiones.reduce(0.0) {
            $0 + max(0, saldo(de: $1, movimientos: movimientos)) * $1.rendimientoAnual
        }
        return suma / total
    }

    /// Rendimiento bruto que genera un saldo a cierta tasa anual, en N días.
    static func rendimiento(saldo: Double, tasaAnual: Double, dias: Double) -> Double {
        saldo * (tasaAnual / 100) * (dias / 365)
    }

    struct PuntoProyeccion: Identifiable {
        var id: Int { mes }
        let mes: Int
        let monto: Double
    }

    /// Proyección con interés compuesto mensual (así es como capitalizan casi todas).
    static func proyeccion(saldo: Double, tasaAnual: Double, meses: Int) -> [PuntoProyeccion] {
        let tasaMensual = tasaAnual / 100 / 12
        return (0...meses).map { n in
            PuntoProyeccion(mes: n, monto: saldo * pow(1 + tasaMensual, Double(n)))
        }
    }

    // MARK: - Suscripciones

    static func costoMensualTotal(_ suscripciones: [Suscripcion]) -> Double {
        suscripciones.filter(\.activa).reduce(0) { $0 + $1.costoMensual }
    }
}
