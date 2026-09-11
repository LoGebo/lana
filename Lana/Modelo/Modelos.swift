import Foundation
import SwiftData

// MARK: - Enums

enum TipoCuenta: String, Codable, CaseIterable, Identifiable {
    case debito, credito, efectivo, inversion

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .debito: "Débito"
        case .credito: "Crédito"
        case .efectivo: "Efectivo"
        case .inversion: "Inversión"
        }
    }

    var icono: String {
        switch self {
        case .debito: "creditcard"
        case .credito: "creditcard.fill"
        case .efectivo: "banknote"
        case .inversion: "chart.line.uptrend.xyaxis"
        }
    }

    /// Las de crédito se muestran como deuda (saldo negativo = debes).
    var esDeuda: Bool { self == .credito }
}

enum TipoMovimiento: String, Codable, CaseIterable, Identifiable {
    case gasto, ingreso, transferencia

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .gasto: "Gasto"
        case .ingreso: "Ingreso"
        case .transferencia: "Transfer"
        }
    }

    var icono: String {
        switch self {
        case .gasto: "arrow.up.right"
        case .ingreso: "arrow.down.left"
        case .transferencia: "arrow.left.arrow.right"
        }
    }
}

enum CicloCobro: String, Codable, CaseIterable, Identifiable {
    case semanal, mensual, bimestral, trimestral, semestral, anual

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .semanal: "Semanal"
        case .mensual: "Mensual"
        case .bimestral: "Bimestral"
        case .trimestral: "Trimestral"
        case .semestral: "Semestral"
        case .anual: "Anual"
        }
    }

    /// Cuántos meses cubre un cobro, para normalizar todo a costo mensual.
    var mesesQueCubre: Double {
        switch self {
        case .semanal: 12.0 / 52.0
        case .mensual: 1
        case .bimestral: 2
        case .trimestral: 3
        case .semestral: 6
        case .anual: 12
        }
    }

    func siguienteFecha(desde fecha: Date, calendario: Calendar = .current) -> Date {
        switch self {
        case .semanal: calendario.date(byAdding: .day, value: 7, to: fecha) ?? fecha
        case .mensual: calendario.date(byAdding: .month, value: 1, to: fecha) ?? fecha
        case .bimestral: calendario.date(byAdding: .month, value: 2, to: fecha) ?? fecha
        case .trimestral: calendario.date(byAdding: .month, value: 3, to: fecha) ?? fecha
        case .semestral: calendario.date(byAdding: .month, value: 6, to: fecha) ?? fecha
        case .anual: calendario.date(byAdding: .year, value: 1, to: fecha) ?? fecha
        }
    }
}

// MARK: - Categoría

@Model
final class Categoria {
    var id: UUID = UUID()
    var nombre: String = ""
    var emoji: String = "📦"
    var colorHex: String = "#8E8E93"
    /// 0 = sin presupuesto.
    var presupuestoMensual: Double = 0
    var esIngreso: Bool = false
    var orden: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Movimiento.categoria)
    var movimientos: [Movimiento]? = []

    @Relationship(deleteRule: .nullify, inverse: \Suscripcion.categoria)
    var suscripciones: [Suscripcion]? = []

    init(nombre: String,
         emoji: String = "📦",
         colorHex: String = "#8E8E93",
         presupuestoMensual: Double = 0,
         esIngreso: Bool = false,
         orden: Int = 0) {
        self.id = UUID()
        self.nombre = nombre
        self.emoji = emoji
        self.colorHex = colorHex
        self.presupuestoMensual = presupuestoMensual
        self.esIngreso = esIngreso
        self.orden = orden
    }
}

// MARK: - Cuenta

@Model
final class Cuenta {
    var id: UUID = UUID()
    var nombre: String = ""
    var institucion: String = ""
    var tipoRaw: String = TipoCuenta.debito.rawValue
    /// Lo que ya tenías el día que empezaste a usar la app.
    var saldoInicial: Double = 0
    /// Rendimiento anual en porcentaje (14.5 = 14.5% anual).
    var rendimientoAnual: Double = 0
    var colorHex: String = "#0A84FF"
    var activa: Bool = true
    var orden: Int = 0
    var notas: String = ""
    /// Fecha a la que corresponde `saldoInicial`. Desde aquí corre el
    /// rendimiento; al corregir el saldo se re-basea a hoy.
    var fechaBase: Date = Date()
    /// Si la cuenta va sumando su rendimiento día con día.
    var acumulaRendimiento: Bool = true

    @Relationship(deleteRule: .nullify, inverse: \Movimiento.cuenta)
    var movimientos: [Movimiento]? = []

    var tipo: TipoCuenta {
        get { TipoCuenta(rawValue: tipoRaw) ?? .debito }
        set { tipoRaw = newValue.rawValue }
    }

    init(nombre: String,
         institucion: String = "",
         tipo: TipoCuenta = .debito,
         saldoInicial: Double = 0,
         rendimientoAnual: Double = 0,
         colorHex: String = "#0A84FF",
         orden: Int = 0) {
        self.id = UUID()
        self.nombre = nombre
        self.institucion = institucion
        self.tipoRaw = tipo.rawValue
        self.saldoInicial = saldoInicial
        self.rendimientoAnual = rendimientoAnual
        self.colorHex = colorHex
        self.activa = true
        self.orden = orden
        self.notas = ""
    }
}

// MARK: - Movimiento

@Model
final class Movimiento {
    var id: UUID = UUID()
    var monto: Double = 0
    var fecha: Date = Date()
    var tipoRaw: String = TipoMovimiento.gasto.rawValue
    var comercio: String = ""
    var nota: String = ""
    /// Solo para transferencias: a qué cuenta llegó la lana.
    var cuentaDestinoID: UUID?
    /// true si vino de Siri / Atajos (para saber qué falta revisar).
    var creadoPorAtajo: Bool = false

    var cuenta: Cuenta?
    var categoria: Categoria?

    var tipo: TipoMovimiento {
        get { TipoMovimiento(rawValue: tipoRaw) ?? .gasto }
        set { tipoRaw = newValue.rawValue }
    }

    init(monto: Double,
         fecha: Date = Date(),
         tipo: TipoMovimiento = .gasto,
         comercio: String = "",
         nota: String = "",
         cuenta: Cuenta? = nil,
         categoria: Categoria? = nil,
         cuentaDestinoID: UUID? = nil,
         creadoPorAtajo: Bool = false) {
        self.id = UUID()
        self.monto = monto
        self.fecha = fecha
        self.tipoRaw = tipo.rawValue
        self.comercio = comercio
        self.nota = nota
        self.cuenta = cuenta
        self.categoria = categoria
        self.cuentaDestinoID = cuentaDestinoID
        self.creadoPorAtajo = creadoPorAtajo
    }
}

// MARK: - Suscripción

@Model
final class Suscripcion {
    var id: UUID = UUID()
    var nombre: String = ""
    var monto: Double = 0
    var cicloRaw: String = CicloCobro.mensual.rawValue
    var proximoCobro: Date = Date()
    var activa: Bool = true
    var cuentaID: UUID?
    var notas: String = ""

    var categoria: Categoria?

    var ciclo: CicloCobro {
        get { CicloCobro(rawValue: cicloRaw) ?? .mensual }
        set { cicloRaw = newValue.rawValue }
    }

    /// Cuánto te cuesta al mes, sin importar cada cuándo te lo cobren.
    var costoMensual: Double { monto / ciclo.mesesQueCubre }

    var diasParaCobro: Int {
        let hoy = Calendar.current.startOfDay(for: Date())
        let cobro = Calendar.current.startOfDay(for: proximoCobro)
        return Calendar.current.dateComponents([.day], from: hoy, to: cobro).day ?? 0
    }

    init(nombre: String,
         monto: Double,
         ciclo: CicloCobro = .mensual,
         proximoCobro: Date = Date(),
         cuentaID: UUID? = nil,
         categoria: Categoria? = nil) {
        self.id = UUID()
        self.nombre = nombre
        self.monto = monto
        self.cicloRaw = ciclo.rawValue
        self.proximoCobro = proximoCobro
        self.cuentaID = cuentaID
        self.categoria = categoria
        self.activa = true
        self.notas = ""
    }
}
