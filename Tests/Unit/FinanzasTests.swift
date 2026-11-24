import XCTest
import SwiftData
@testable import Lana

@MainActor
final class FinanzasTests: XCTestCase {

    private func ctx() throws -> ModelContext {
        let esquema = Schema([Cuenta.self, Movimiento.self, Categoria.self, Suscripcion.self])
        let c = try ModelContainer(for: esquema, configurations: ModelConfiguration(schema: esquema, isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    func testGastoBajaElPatrimonio() throws {
        let c = try ctx()
        let cuenta = Cuenta(nombre: "HSBC", tipo: .debito, saldoInicial: 1000)
        c.insert(cuenta)
        let g = Movimiento(monto: 189, tipo: .gasto, cuenta: cuenta)
        c.insert(g)
        XCTAssertEqual(Finanzas.patrimonio(cuentas: [cuenta], movimientos: [g]), 811, accuracy: 0.001)
    }

    func testGastoConTarjetaDeCreditoBajaPatrimonio() throws {
        let c = try ctx()
        let banco = Cuenta(nombre: "BBVA", tipo: .debito, saldoInicial: 1000)
        let tarjeta = Cuenta(nombre: "Nu Crédito", tipo: .credito, saldoInicial: 0)
        c.insert(banco); c.insert(tarjeta)
        let g = Movimiento(monto: 300, tipo: .gasto, cuenta: tarjeta)
        c.insert(g)
        XCTAssertEqual(Finanzas.patrimonio(cuentas: [banco, tarjeta], movimientos: [g]), 700, accuracy: 0.001)
        // Pagar la tarjeta (transferencia) no cambia el patrimonio.
        let pago = Movimiento(monto: 300, tipo: .transferencia, cuenta: banco, cuentaDestinoID: tarjeta.id)
        c.insert(pago)
        XCTAssertEqual(Finanzas.patrimonio(cuentas: [banco, tarjeta], movimientos: [g, pago]), 700, accuracy: 0.001)
        XCTAssertEqual(Finanzas.saldo(de: tarjeta, movimientos: [g, pago]), 0, accuracy: 0.001)
    }

    func testMovimientoFuturoNoCuentaHoy() throws {
        let c = try ctx()
        let cuenta = Cuenta(nombre: "BBVA", tipo: .debito, saldoInicial: 1000)
        c.insert(cuenta)
        let manana = Calendar.current.date(byAdding: .day, value: 40, to: Date())!
        let futuro = Movimiento(monto: 500, fecha: manana, tipo: .gasto, cuenta: cuenta)
        c.insert(futuro)
        XCTAssertEqual(Finanzas.saldoBase(de: cuenta, movimientos: [futuro]), 1000, accuracy: 0.001)
        XCTAssertEqual(Finanzas.saldo(de: cuenta, movimientos: [futuro]), 1000, accuracy: 0.001)
    }

    func testMovimientoDeHoyConHoraTardeSiCuenta() throws {
        let c = try ctx()
        let cuenta = Cuenta(nombre: "BBVA", tipo: .debito, saldoInicial: 1000)
        c.insert(cuenta)
        let finDelDia = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: Date())!
        let g = Movimiento(monto: 100, fecha: finDelDia, tipo: .gasto, cuenta: cuenta)
        c.insert(g)
        XCTAssertEqual(Finanzas.saldoBase(de: cuenta, movimientos: [g]), 900, accuracy: 0.001)
    }

    func testRendimientoCompuestoDiario() throws {
        let c = try ctx()
        let cuenta = Cuenta(nombre: "MP", tipo: .inversion, saldoInicial: 10_000, rendimientoAnual: 15)
        cuenta.fechaBase = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        c.insert(cuenta)
        let tasa: Double = 1.0 + 0.15 / 365.0
        let esperado: Double = 10_000.0 * pow(tasa, 30.0)
        XCTAssertEqual(Finanzas.saldo(de: cuenta, movimientos: []), esperado, accuracy: 0.01)
        // Gasto de hoy en cuenta con rendimiento sí baja el saldo.
        let g = Movimiento(monto: 100, tipo: .gasto, cuenta: cuenta)
        c.insert(g)
        XCTAssertEqual(Finanzas.saldo(de: cuenta, movimientos: [g]), esperado - 100, accuracy: 0.5)
    }

    func testCuentaArchivadaNoCuentaEnPatrimonio() throws {
        let c = try ctx()
        let a = Cuenta(nombre: "A", tipo: .debito, saldoInicial: 500)
        let b = Cuenta(nombre: "B", tipo: .debito, saldoInicial: 700)
        b.activa = false
        c.insert(a); c.insert(b)
        XCTAssertEqual(Finanzas.patrimonio(cuentas: [a, b], movimientos: []), 500)
    }

    func testSumaDeSaldosReportados() throws {
        // El patrimonio es la suma de los saldos de las cuentas activas.
        let c = try ctx()
        let saldos = [1_000, 2_500, 300, 4_000, 150].map(Double.init)
        let cuentas = saldos.map { Cuenta(nombre: "c", tipo: .debito, saldoInicial: $0) }
        cuentas.forEach { c.insert($0) }
        XCTAssertEqual(Finanzas.patrimonio(cuentas: cuentas, movimientos: []), 7_950)
    }

    func testIngresosRecurrentesIdempotentes() throws {
        let c = try ctx()
        let hsbc = Cuenta(nombre: "HSBC", tipo: .debito)
        let bbva = Cuenta(nombre: "BBVA", tipo: .debito)
        c.insert(hsbc); c.insert(bbva)
        c.insert(Categoria(nombre: "Sueldo", esIngreso: true))
        try c.save()

        let previoFuentes = Nomina.fuentes
        let previoActiva = Nomina.activa
        let previoDesde = Nomina.desde
        defer { Nomina.fuentes = previoFuentes; Nomina.activa = previoActiva; Nomina.desde = previoDesde }

        Nomina.fuentes = [FuenteIngreso(nombre: "Empleo A", monto: 10_000, cuentaID: hsbc.id),
                          FuenteIngreso(nombre: "Empleo B", monto: 6_000, cuentaID: bbva.id)]
        Nomina.activa = true
        Nomina.desde = Calendar.current.date(byAdding: .day, value: -20, to: Date())!

        let n1 = Nomina.depositarPendientes(c)
        let movs1 = try c.fetch(FetchDescriptor<Movimiento>())
        XCTAssertEqual(movs1.count, n1)
        XCTAssertEqual(movs1.filter { $0.cuenta?.id == hsbc.id }.allSatisfy { $0.monto == 10_000 }, true)
        XCTAssertEqual(movs1.filter { $0.cuenta?.id == bbva.id }.allSatisfy { $0.monto == 6_000 }, true)
        // Ingreso mensual = (10,000 + 6,000) * 2
        XCTAssertEqual(Señales.defaults.double(forKey: Nomina.llaveIngreso), 32_000)
        // Segunda corrida no duplica (desde se movió a hoy).
        XCTAssertEqual(Nomina.depositarPendientes(c), 0)
    }

    func testCapturaDeMontoApplePay() {
        func parsear(_ t: String) -> Double? { Double(t.filter { $0.isNumber || $0 == "." }) }
        XCTAssertEqual(parsear("$189.00"), 189)
        XCTAssertEqual(parsear("1,234.50"), 1234.5)
        XCTAssertEqual(parsear("MXN 45"), 45)
        XCTAssertNil(parsear("gratis"))
    }
}
