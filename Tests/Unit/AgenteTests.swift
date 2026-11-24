import XCTest
import SwiftData
@testable import Lana

@MainActor
final class AgenteTests: XCTestCase {
    private var fin: ModelContext!, pro: ModelContext!, def: UserDefaults!

    override func setUpWithError() throws {
        let e1 = Schema([Cuenta.self, Movimiento.self, Categoria.self, Suscripcion.self])
        fin = ModelContext(try ModelContainer(for: e1, configurations: ModelConfiguration(schema: e1, isStoredInMemoryOnly: true)))
        let e2 = Schema([HabitoLog.self, EjercicioDef.self, Rutina.self, SesionGym.self, EjercicioLog.self, Serie.self,
                         Alimento.self, ComidaLog.self, AguaLog.self, PesoLog.self])
        pro = ModelContext(try ModelContainer(for: e2, configurations: ModelConfiguration(schema: e2, isStoredInMemoryOnly: true)))
        def = UserDefaults(suiteName: "agente-test-\(UUID())")!
    }

    private func go(_ id: String, _ tool: String, _ a: [String: Any]) -> ResultadoAgente {
        AplicadorAgente.aplicar(id: id, tool: tool, args: a, finanzas: fin, protocolos: pro, defaults: def)
    }

    func testGastoValidoSeAplicaUnaVezAunqueSeReintente() throws {
        fin.insert(Cuenta(nombre: "Débito", tipo: .debito, saldoInicial: 0)); try fin.save()
        XCTAssertEqual(go("k1", "log_expense", ["amount": 120.5, "note": "tacos"]), .aplicado)
        XCTAssertEqual(go("k1", "log_expense", ["amount": 120.5, "note": "tacos"]), .duplicado)
        let m = try fin.fetch(FetchDescriptor<Movimiento>())
        XCTAssertEqual(m.count, 1); XCTAssertEqual(m[0].monto, 120.5); XCTAssertTrue(m[0].nota.hasPrefix("[agente]"))
    }

    func testMontosInvalidosSeRechazanYNoCreanNada() throws {
        fin.insert(Cuenta(nombre: "Débito", tipo: .debito, saldoInicial: 0)); try fin.save()
        for (i, v) in [-5.0, 0, .nan, .infinity, 50_001].enumerated() {
            if case .rechazado = go("m\(i)", "log_expense", ["amount": v]) {} else { XCTFail("aceptó \(v)") }
        }
        XCTAssertEqual(go("m9", "log_expense", ["amount": "10"]), .rechazado("monto inválido"))
        XCTAssertEqual(try fin.fetch(FetchDescriptor<Movimiento>()).count, 0)
    }

    func testGastoSinCuentasSeRechaza() { XCTAssertEqual(go("s1", "log_expense", ["amount": 10]), .rechazado("no hay cuentas")) }

    func testComandoDesconocidoYPeso() {
        XCTAssertEqual(go("u1", "delete_all", [:]), .rechazado("herramienta desconocida"))
        XCTAssertEqual(go("u2", "log_weight", ["kg": 5]), .rechazado("peso inválido"))
        XCTAssertEqual(go("u3", "log_weight", ["kg": 75.4]), .aplicado)
        XCTAssertEqual(try pro.fetch(FetchDescriptor<PesoLog>()).map(\.kg), [75.4])
    }

    func testFechaFuturaRechazada() {
        XCTAssertEqual(go("f1", "log_water", ["ml": 250, "occurred_at": "2999-01-01T00:00:00.000Z"]), .rechazado("fecha futura"))
        XCTAssertEqual(go("f2", "log_water", ["ml": 250, "occurred_at": "ayer"]), .rechazado("fecha inválida"))
    }

    func testAguaComidaYSeriesVanALaBaseDeProtocolos() throws {
        XCTAssertEqual(go("a1", "log_water", ["ml": 500]), .aplicado)
        XCTAssertEqual(go("a2", "log_water", ["ml": 5000]), .rechazado("ml inválido"))
        XCTAssertEqual(go("c1", "log_meal", ["name": "Huevos", "kcal": 300, "protein_g": 25, "meal": "desayuno"]), .aplicado)
        XCTAssertEqual(go("w1", "log_workout_set", ["exercise": "Press inclinado", "reps": 8, "weight_kg": 40.0, "workout_name": "Upper"]), .aplicado)
        XCTAssertEqual(go("w2", "log_workout_set", ["exercise": "Press inclinado", "reps": 7, "weight_kg": 40.0, "workout_name": "Upper"]), .aplicado)
        XCTAssertEqual(go("w3", "log_workout_set", ["exercise": "X", "reps": 0, "weight_kg": 40.0]), .rechazado("serie inválida"))
        XCTAssertEqual(try pro.fetch(FetchDescriptor<AguaLog>()).map(\.ml), [500])
        XCTAssertEqual(try pro.fetch(FetchDescriptor<ComidaLog>()).first?.proteina, 25)
        let ses = try pro.fetch(FetchDescriptor<SesionGym>())
        XCTAssertEqual(ses.count, 1)                       // las dos series comparten sesión y ejercicio
        XCTAssertEqual(ses[0].ejercicios?.count, 1)
        XCTAssertEqual(ses[0].ejercicios?.first?.series?.count, 2)
        XCTAssertNotNil(ses[0].fin)                        // no se queda "en curso"
    }
}
