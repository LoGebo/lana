import XCTest
import SwiftData
@testable import Lana

final class ProgramaTests: XCTestCase {
    func testTodasLasSemanasTienenFaseYCincoDias() throws {
        try XCTSkipIf(Programa.fases.isEmpty, "programa no incluido en el repo")
        for w in 1...12 {
            let f = Programa.fase(de: w)
            XCTAssertNotNil(f, "semana \(w)")
            XCTAssertEqual(f?.dias.count, 5)
        }
    }
    func testCadaEjercicioTieneVideoYAlternativas() throws {
        try XCTSkipIf(Programa.fases.isEmpty, "programa no incluido en el repo")
        for f in Programa.fases { for (_, ejs) in f.dias { for e in ejs {
            let i = Programa.catalogo[e.n]
            XCTAssertNotNil(i, e.n)
            XCTAssertNotNil(URL(string: i?.url ?? ""), e.n)
            XCTAssertEqual(i?.alt.count, 2, e.n)
            XCTAssertGreaterThan(e.d, 0); XCTAssertGreaterThan(e.s, 0)
        } } }
    }
    func testRIRDesdeRPE() {
        XCTAssertEqual(Programa.rir(desdeRPE: "10"), "0")
        XCTAssertEqual(Programa.rir(desdeRPE: "~8-9"), "1-2")
        XCTAssertEqual(Programa.rir(desdeRPE: "~7-8"), "2-3")
    }
    func testGrupos() {
        XCTAssertEqual(Programa.grupo(de: "Standing Calf Raise"), "Pantorrilla")
        XCTAssertEqual(Programa.grupo(de: "Lying Leg Curl"), "Isquios")
        XCTAssertEqual(Programa.grupo(de: "Hack Squat"), "Piernas")
        XCTAssertEqual(Programa.grupo(de: "Bayesian Cable Curl"), "Bíceps")
        XCTAssertEqual(Programa.grupo(de: "Machine Chest Press"), "Pecho")
    }
}

final class CalentamientoTests: XCTestCase {
    func testPiramideRedondeaA2_5() {
        let s = Programa.seriesDeCalentamiento("2-3", pesoTrabajo: 100)   // 3 series: 45/65/85 %
        XCTAssertEqual(s.map(\.peso), [45, 65, 85])
        XCTAssertEqual(s.map(\.reps), [8, 5, 3])
        XCTAssertEqual(Programa.seriesDeCalentamiento("1-2", pesoTrabajo: 62.5).map(\.peso), [32.5, 45])  // 31.25→32.5, 43.75→45 (redondeo al más cercano, mitades hacia arriba)
        XCTAssertEqual(Programa.seriesDeCalentamiento("1", pesoTrabajo: 40).map(\.peso), [25])
    }
    func testSinPesoPrevioOSinPlan() {
        XCTAssertEqual(Programa.seriesDeCalentamiento("2-4", pesoTrabajo: 0).map(\.peso), [0, 0, 0, 0])
        XCTAssertTrue(Programa.seriesDeCalentamiento(nil, pesoTrabajo: 100).isEmpty)
    }
}

@MainActor
final class AplicarProgramaTests: XCTestCase {
    private func contexto() throws -> ModelContext {
        let esquema = Schema([HabitoLog.self, EjercicioDef.self, Rutina.self, SesionGym.self, EjercicioLog.self, Serie.self, Alimento.self, ComidaLog.self, AguaLog.self])
        let c = try ModelContainer(for: esquema, configurations: ModelConfiguration(schema: esquema, isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    func testAplicarCreaSeisRutinasYCambiaConLaSemana() throws {
        try XCTSkipIf(Programa.fases.isEmpty, "programa no incluido en el repo")
        let ctx = try contexto()
        Programa.aplicar(semana: 1, ctx)
        var r = try ctx.fetch(FetchDescriptor<Rutina>())
        XCTAssertEqual(Set(r.map(\.nombre)), ["BTS Upper", "BTS Lower", "BTS Pull", "BTS Push", "BTS Legs", "BTS Brazos + puntos débiles (extra)"])
        let upper1 = try XCTUnwrap(r.first { $0.nombre == "BTS Upper" })
        XCTAssertEqual(upper1.plan["45° Incline Barbell Press"]?.series, 2)

        Programa.aplicar(semana: 12, ctx)          // misma rutina, otra fase: no duplica
        r = try ctx.fetch(FetchDescriptor<Rutina>())
        XCTAssertEqual(r.count, 6)
        let upper12 = try XCTUnwrap(r.first { $0.nombre == "BTS Upper" })
        XCTAssertEqual(upper12.plan["45° Incline DB Press"]?.series, 4)
        XCTAssertEqual(upper12.plan["45° Incline DB Press"]?.tecnica, "Failure")
        let defs = Set(try ctx.fetch(FetchDescriptor<EjercicioDef>()).map(\.nombre))
        XCTAssertTrue(upper12.ejercicios.allSatisfy(defs.contains), "faltan ejercicios en la biblioteca")
        limpiar()
    }

    private func limpiar() {
        for k in [Programa.llave, Programa.llave + ".aplicada", Programa.llaveInicio] { UserDefaults.standard.removeObject(forKey: k) }
    }

    func testQuitaRutinasViejasSinEditarYConservaLasEditadas() throws {
        try XCTSkipIf(Programa.fases.isEmpty, "programa no incluido en el repo")
        let ctx = try contexto()
        let viejo = Biblioteca.rutinasCiencia[0], otra = Biblioteca.rutinasCiencia[1]
        ctx.insert(Rutina(nombre: viejo.nombre, ejercicios: viejo.items.map(\.0)))            // sin tocar → se va
        ctx.insert(Rutina(nombre: otra.nombre, ejercicios: viejo.items.map(\.0) + ["Mi ejercicio"]))  // editada → se queda
        ctx.insert(Rutina(nombre: "Mi rutina", ejercicios: ["X"]))
        Programa.aplicar(semana: 1, ctx)
        let nombres = Set(try ctx.fetch(FetchDescriptor<Rutina>()).map(\.nombre))
        XCTAssertFalse(nombres.contains(viejo.nombre))
        XCTAssertTrue(nombres.contains(otra.nombre)); XCTAssertTrue(nombres.contains("Mi rutina"))
        limpiar()
    }

    func testSemanaPorFechaAvanzaSolaYTopeEn12() throws {
        try XCTSkipIf(Programa.fases.isEmpty, "programa no incluido en el repo")
        let hoy = Calendar.current.startOfDay(for: Date())
        func inicio(haceDias d: Int) { UserDefaults.standard.set(Calendar.current.date(byAdding: .day, value: -d, to: hoy)!.timeIntervalSince1970, forKey: Programa.llaveInicio) }
        inicio(haceDias: 0);  XCTAssertEqual(Programa.semanaPorFecha(), 1)
        inicio(haceDias: 6);  XCTAssertEqual(Programa.semanaPorFecha(), 1)
        inicio(haceDias: 7);  XCTAssertEqual(Programa.semanaPorFecha(), 2)
        inicio(haceDias: 15); XCTAssertEqual(Programa.semanaPorFecha(), 3)
        inicio(haceDias: 400); XCTAssertEqual(Programa.semanaPorFecha(), 12)
        // aplicar(semana: 5) fija el inicio de modo que la fecha confirme la semana 5
        Programa.aplicar(semana: 5, try contexto()); XCTAssertEqual(Programa.semanaPorFecha(), 5)
        limpiar()
    }

    func testSesionConCalentamientoYSerieAlFallo() throws {
        let ctx = try contexto()
        let plan = ItemPlan(series: 2, reps: "6-8", rir: "0", descanso: 180, grupo: "Pecho", rpe: "~8-9 → 10", tecnica: "Failure", calentamiento: "2-3")
        let s = SesionGym(nombre: "t"); ctx.insert(s)
        agregarEjercicio(nombre: "Press", grupo: "Pecho", a: s, orden: 0, contexto: ctx, historial: [], plan: plan)
        let series = try XCTUnwrap(s.ejerciciosOrdenados.first).seriesOrdenadas
        XCTAssertEqual(series.map(\.tipo), [.calentamiento, .calentamiento, .calentamiento, .normal, .fallo])
        XCTAssertEqual(series.map(\.orden), [0, 1, 2, 3, 4])
    }
}
