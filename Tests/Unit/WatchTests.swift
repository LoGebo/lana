import XCTest
import SwiftData
@testable import Lana

@MainActor
final class WatchTests: XCTestCase {
    private var fin: ModelContext!, pro: ModelContext!, def: UserDefaults!

    override func setUpWithError() throws {
        let e1 = Schema([Cuenta.self, Movimiento.self, Categoria.self, Suscripcion.self])
        fin = ModelContext(try ModelContainer(for: e1, configurations: ModelConfiguration(schema: e1, isStoredInMemoryOnly: true)))
        let e2 = Schema([HabitoLog.self, EjercicioDef.self, Rutina.self, SesionGym.self, EjercicioLog.self, Serie.self,
                         Alimento.self, ComidaLog.self, AguaLog.self, PesoLog.self])
        pro = ModelContext(try ModelContainer(for: e2, configurations: ModelConfiguration(schema: e2, isStoredInMemoryOnly: true)))
        def = UserDefaults(suiteName: "watch-test-\(UUID())")!
    }

    private func aplicar(_ c: ComandoWatch) -> ResultadoAgente {
        AplicadorAgente.aplicar(id: c.id, tool: c.tool, args: c.argsAny, finanzas: fin, protocolos: pro, defaults: def)
    }

    // MARK: validación y codificación

    func testValidacionBorde() {
        XCTAssertNil(ComandoWatch.agua(ml: 250).validar())
        for ml in [0.0, -250, .nan, .infinity, 2001] { XCTAssertNotNil(ComandoWatch.agua(ml: ml).validar(), "ml \(ml)") }
        for m in [0.0, -1, .nan, 50_001] { XCTAssertNotNil(ComandoWatch.gasto(monto: m, categoria: nil).validar(), "monto \(m)") }
        XCTAssertNil(ComandoWatch.gasto(monto: 50_000, categoria: "Comida").validar())
        XCTAssertNil(ComandoWatch.serie(ejercicio: "Press", rutina: "BTS Push", kg: 0, reps: 1).validar())
        XCTAssertNotNil(ComandoWatch.serie(ejercicio: "Press", rutina: "x", kg: 501, reps: 8).validar())
        XCTAssertNotNil(ComandoWatch.serie(ejercicio: "Press", rutina: "x", kg: 50, reps: 0).validar())
        XCTAssertNotNil(ComandoWatch.serie(ejercicio: "Press", rutina: "x", kg: 50, reps: 101).validar())
        XCTAssertNotNil(ComandoWatch.serie(ejercicio: "", rutina: "x", kg: 50, reps: 8).validar())
        XCTAssertNotNil(ComandoWatch.peso(kg: 29.9).validar()); XCTAssertNil(ComandoWatch.peso(kg: 75.4).validar())
        XCTAssertNotNil(ComandoWatch(id: "x", tool: "delete_all", args: [:]).validar())
    }

    func testCodificaIdaYVuelta() throws {
        let c = ComandoWatch.gasto(monto: 85.5, categoria: "Comida")
        let d = try JSONDecoder().decode(ComandoWatch.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(c, d)
        XCTAssertEqual(d.argsAny["amount"] as? Double, 85.5)
    }

    // MARK: cola offline

    func testColaPersisteDeduplicaYConfirma() {
        let d = UserDefaults(suiteName: "cola-\(UUID())")!
        let cola = ColaWatch(defaults: d)
        let a = ComandoWatch.agua(ml: 250), b = ComandoWatch.peso(kg: 75)
        XCTAssertTrue(cola.encolar(a)); XCTAssertTrue(cola.encolar(a)); XCTAssertTrue(cola.encolar(b))
        XCTAssertEqual(ColaWatch(defaults: d).pendientes.map(\.id), [a.id, b.id])      // sobrevive reinicio
        XCTAssertFalse(cola.encolar(ComandoWatch.agua(ml: -1)))                          // inválido no entra
        cola.confirmar([a.id, "no-existe"])
        XCTAssertEqual(cola.pendientes.map(\.id), [b.id])
        cola.confirmar([]); XCTAssertEqual(cola.pendientes.count, 1)
    }

    func testColaLlenaRechazaSinPerderLoGuardado() {
        let d = UserDefaults(suiteName: "cola-\(UUID())")!
        let cola = ColaWatch(defaults: d)
        for i in 0..<ColaWatch.tope { XCTAssertTrue(cola.encolar(.agua(ml: 1, id: "\(i)"))) }
        XCTAssertFalse(cola.encolar(.agua(ml: 1, id: "extra")))
        XCTAssertEqual(cola.pendientes.count, ColaWatch.tope); XCTAssertEqual(cola.pendientes.first?.id, "0")
    }

    // MARK: aplicación idempotente en el iPhone

    func testReenvioDelRelojNoDuplica() throws {
        fin.insert(Cuenta(nombre: "Débito", tipo: .debito, saldoInicial: 0)); try fin.save()
        let g = ComandoWatch.gasto(monto: 99, categoria: nil), w = ComandoWatch.agua(ml: 250)
        XCTAssertEqual(aplicar(g), .aplicado); XCTAssertEqual(aplicar(g), .duplicado)   // sendMessage + transferUserInfo
        XCTAssertEqual(aplicar(w), .aplicado); XCTAssertEqual(aplicar(w), .duplicado)
        let m = try fin.fetch(FetchDescriptor<Movimiento>())
        XCTAssertEqual(m.count, 1); XCTAssertTrue(m[0].nota.hasPrefix("[watch]"))
        XCTAssertEqual(try pro.fetch(FetchDescriptor<AguaLog>()).count, 1)
    }

    func testSeriesDelRelojAgrupanEnUnaSesion() throws {
        for (i, r) in [8, 8, 7].enumerated() { XCTAssertEqual(aplicar(.serie(ejercicio: "Press inclinado", rutina: "BTS Upper", kg: 60, reps: r, id: "s\(i)")), .aplicado) }
        XCTAssertEqual(aplicar(.serie(ejercicio: "Curl", rutina: "BTS Upper", kg: 20, reps: 12, id: "s9")), .aplicado)
        let ses = try pro.fetch(FetchDescriptor<SesionGym>())
        XCTAssertEqual(ses.count, 1); XCTAssertEqual(ses[0].ejerciciosOrdenados.map(\.nombre), ["Press inclinado", "Curl"])
        XCTAssertEqual(ses[0].ejerciciosOrdenados[0].seriesOrdenadas.map(\.reps), [8, 8, 7])
    }

    func testPesoYFechaFuturaDelReloj() throws {
        XCTAssertEqual(aplicar(.peso(kg: 75.2)), .aplicado)
        XCTAssertEqual(try pro.fetch(FetchDescriptor<PesoLog>()).map(\.kg), [75.2])
        XCTAssertEqual(aplicar(.agua(ml: 250, ahora: Date().addingTimeInterval(3 * 86400))), .rechazado("fecha futura"))
    }

    func testReintentoSinCuentaNoPierdeElId() throws {
        let g = ComandoWatch.gasto(monto: 10, categoria: nil)
        XCTAssertEqual(aplicar(g), .rechazado("no hay cuentas"))      // rechazado no se marca como visto…
        fin.insert(Cuenta(nombre: "Débito", tipo: .debito, saldoInicial: 0)); try fin.save()
        XCTAssertEqual(aplicar(g), .aplicado)                           // …así que un reenvío posterior sí entra
    }

    // MARK: resumen y sueño

    func testResumenDelDia() throws {
        def.set(2000.0, forKey: LlavesMetas.kcal); def.set(150.0, forKey: LlavesMetas.proteina)
        pro.insert(ComidaLog(dia: Date(), tiempo: .comida, nombre: "Pollo", porcionTexto: "100 g", porciones: 2, kcal: 165, proteina: 31, carbs: 0, grasa: 3.6))
        pro.insert(AguaLog(dia: Date(), ml: 500)); pro.insert(AguaLog(dia: Date(), ml: 250))
        fin.insert(Categoria(nombre: "Comida")); try pro.save(); try fin.save()
        let r = PuenteWatch.construirResumen(finanzas: fin, protocolos: pro, defaults: def)
        XCTAssertEqual(r.kcal, 330); XCTAssertEqual(r.proteina, 62); XCTAssertEqual(r.kcalMeta, 2000)
        XCTAssertEqual(r.aguaMl, 750); XCTAssertEqual(r.categorias, ["Comida"])
        XCTAssertEqual(try JSONDecoder().decode(ResumenWatch.self, from: JSONEncoder().encode(r)), r)
    }

    func testHorasDeSuenoUneTraslapes() {
        let t = Date(timeIntervalSince1970: 1_000_000), h = 3600.0
        // iPhone y Watch miden la misma noche: no se suma doble.
        XCTAssertEqual(Sueno.horas([(t, t + 7 * h), (t + 1 * h, t + 6 * h), (t + 6.5 * h, t + 8 * h)]), 8, accuracy: 0.001)
        XCTAssertEqual(Sueno.horas([]), 0)
        XCTAssertEqual(Sueno.horas([(t + h, t)]), 0)   // intervalo invertido
    }
}
