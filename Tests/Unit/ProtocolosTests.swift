import XCTest
import SwiftData
@testable import Lana

@MainActor
final class ProtocolosTests: XCTestCase {

    private func contenedor() throws -> ModelContext {
        let esquema = Schema([HabitoLog.self, EjercicioDef.self, Rutina.self, SesionGym.self, EjercicioLog.self,
                              Serie.self, Alimento.self, ComidaLog.self, AguaLog.self])
        let c = try ModelContainer(for: esquema, configurations: ModelConfiguration(schema: esquema, isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    private func sesion(_ ctx: ModelContext, ejercicio: String = "Press de banca con barra",
                        series: [(Double, Int, Bool, TipoSerie)], fin: Date? = Date()) -> SesionGym {
        let s = SesionGym(nombre: "T")
        ctx.insert(s)
        s.fin = fin
        let e = EjercicioLog(nombre: ejercicio, grupo: "Pecho", orden: 0)
        ctx.insert(e); e.sesion = s
        for (i, x) in series.enumerated() {
            let sr = Serie(orden: i, peso: x.0, reps: x.1, tipo: x.3)
            sr.hecha = x.2
            ctx.insert(sr); sr.ejercicio = e
        }
        return s
    }

    // MARK: 1RM y volumen

    func testE1RM() {
        XCTAssertEqual(GymCalculos.e1RM(peso: 100, reps: 1), 100)
        XCTAssertEqual(GymCalculos.e1RM(peso: 100, reps: 10), 100 * (1 + 10.0 / 30), accuracy: 0.001)
        XCTAssertEqual(GymCalculos.e1RM(peso: 0, reps: 10), 0)
        XCTAssertEqual(GymCalculos.e1RM(peso: 100, reps: 0), 0)
        XCTAssertEqual(GymCalculos.e1RM(peso: -5, reps: 5), 0)
    }

    func testVolumenIgnoraCalentamientoYNoMarcadas() throws {
        let ctx = try contenedor()
        let s = sesion(ctx, series: [(40, 10, true, .calentamiento), (100, 5, true, .normal),
                                     (100, 5, false, .normal), (80, 8, true, .drop)])
        XCTAssertEqual(s.volumen, 100 * 5 + 80 * 8)
        XCTAssertEqual(s.seriesHechas.count, 3)
    }

    func testSesionVaciaNoTruena() throws {
        let ctx = try contenedor()
        let s = SesionGym()
        ctx.insert(s)
        XCTAssertEqual(s.volumen, 0)
        XCTAssertTrue(s.seriesHechas.isEmpty)
        XCTAssertTrue(GymCalculos.records(de: s, historial: [s]).isEmpty)
    }

    // MARK: Récords y anterior

    func testPrimeraVezNoEsRecord() throws {
        let ctx = try contenedor()
        let s = sesion(ctx, series: [(100, 5, true, .normal)])
        XCTAssertTrue(GymCalculos.records(de: s, historial: [s]).isEmpty)
    }

    func testRecordDetectaPesoYE1RM() throws {
        let ctx = try contenedor()
        let vieja = sesion(ctx, series: [(100, 5, true, .normal)])
        let nueva = sesion(ctx, series: [(105, 5, true, .normal)])
        let r = GymCalculos.records(de: nueva, historial: [nueva, vieja])
        XCTAssertEqual(r.count, 3)   // peso, 1RM y volumen de serie (reps solo si repites el mismo peso)
        XCTAssertTrue(r.contains { $0.detalle.contains("Peso máximo") })
        XCTAssertTrue(r.contains { $0.detalle.contains("1RM") })
    }

    func testCalentamientoNoCuentaParaRecord() throws {
        let ctx = try contenedor()
        let vieja = sesion(ctx, series: [(100, 5, true, .normal)])
        let nueva = sesion(ctx, series: [(200, 5, true, .calentamiento), (90, 5, true, .normal)])
        XCTAssertTrue(GymCalculos.records(de: nueva, historial: [nueva, vieja]).isEmpty)
    }

    func testRecordIgualNoEsRecord() throws {
        let ctx = try contenedor()
        let vieja = sesion(ctx, series: [(100, 5, true, .normal)])
        let nueva = sesion(ctx, series: [(100, 5, true, .normal)])
        XCTAssertTrue(GymCalculos.records(de: nueva, historial: [nueva, vieja]).isEmpty)
    }

    func testAnteriorIgnoraSesionEnCursoYSeriesSinMarcar() throws {
        let ctx = try contenedor()
        let enCurso = sesion(ctx, series: [(999, 9, true, .normal)], fin: nil)
        let vieja = sesion(ctx, series: [(100, 5, true, .normal), (100, 4, false, .normal)])
        let a = GymCalculos.anterior(de: "Press de banca con barra", en: [enCurso, vieja])
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].peso, 100)
        XCTAssertTrue(GymCalculos.anterior(de: "Otro", en: [vieja]).isEmpty)
    }

    // MARK: Comida

    func testTotalesDiaEscalanPorPorciones() throws {
        let ctx = try contenedor()
        let hoy = Date()
        let a = ComidaLog(dia: hoy, tiempo: .comida, nombre: "A", porcionTexto: "100 g", porciones: 1.5,
                          kcal: 100, proteina: 10, carbs: 20, grasa: 2)
        let b = ComidaLog(dia: hoy, tiempo: .cena, nombre: "B", porcionTexto: "1", porciones: 2,
                          kcal: 50, proteina: 5, carbs: 0, grasa: 1)
        ctx.insert(a); ctx.insert(b)
        let t = TotalesDia([a, b])
        XCTAssertEqual(t.kcal, 250, accuracy: 0.001)
        XCTAssertEqual(t.proteina, 25, accuracy: 0.001)
        XCTAssertEqual(t.carbs, 30, accuracy: 0.001)
        XCTAssertEqual(t.grasa, 5, accuracy: 0.001)
        XCTAssertEqual(TotalesDia([]).kcal, 0)
    }

    func testComidaLogGuardaCopiaDelAlimento() throws {
        let ctx = try contenedor()
        let al = Alimento(nombre: "X", porcion: "1", kcal: 100, proteina: 10, carbs: 0, grasa: 0)
        ctx.insert(al)
        let l = ComidaLog(dia: Date(), tiempo: .snack, nombre: al.nombre, porcionTexto: al.porcion, porciones: 1,
                          kcal: al.kcal, proteina: al.proteina, carbs: al.carbs, grasa: al.grasa)
        al.kcal = 999
        XCTAssertEqual(l.kcalTotal, 100)
    }

    func testBibliotecaSemillaCoherente() {
        for a in Biblioteca.alimentos + Biblioteca.alimentosUSDA {
            let calc = a.3 * 4 + a.4 * 4 + a.5 * 9   // P*4 + C*4 + G*9
            // El alcohol (7 kcal/g) no entra en la fórmula de macros.
            if ["cerveza", "tequila", "vino"].contains(where: { a.0.lowercased().contains($0) }) { continue }
            // Fibra, agua y alcohol hacen que algunos no cuadren exacto; que no se disparen.
            XCTAssertLessThan(abs(calc - a.2), max(60, a.2 * 0.5), "\(a.0): macros \(calc) vs kcal \(a.2)")
            XCTAssertGreaterThanOrEqual(a.2, 0)
            XCTAssertFalse(a.0.isEmpty)
        }
        let nombres = Biblioteca.alimentos.map { $0.0.lowercased() } + Biblioteca.alimentosUSDA.map { $0.0.lowercased() }
        XCTAssertGreaterThan(Biblioteca.alimentosUSDA.count, 150)
        XCTAssertEqual(Set(Biblioteca.ejercicios.map { $0.0 }).count, Biblioteca.ejercicios.count, "ejercicios duplicados")
        XCTAssertEqual(Set(Biblioteca.alimentosUSDA.map { $0.0.lowercased() }).count, Biblioteca.alimentosUSDA.count, "USDA duplicados")
        _ = nombres
    }

    func testRutinasCienciaCompletas() {
        XCTAssertEqual(Biblioteca.rutinasCiencia.map(\.nombre), ["Torso A", "Pierna A", "Torso B", "Pierna B"])
        for r in Biblioteca.rutinasCiencia {
            XCTAssertFalse(r.items.isEmpty)
            var series = 0
            for (n, p) in r.items {
                XCTAssertGreaterThan(p.series, 0, n); XCTAssertGreaterThanOrEqual(p.descanso, 45, n)
                XCTAssertFalse(p.reps.isEmpty); XCTAssertFalse(p.grupo.isEmpty)
                series += p.series
            }
            XCTAssertLessThanOrEqual(series, 26, "\(r.nombre) pasa de ~60 min")
        }
    }

    func testSembradoIdempotenteYActualizaRutinasSinTocar() throws {
        let ctx = try contenedor()
        let d = UserDefaults.standard
        let llaves = ["protocolos.semilla.v1", "protocolos.semilla.v2"]
        let prev = llaves.map { d.object(forKey: $0) }
        llaves.forEach { d.removeObject(forKey: $0) }
        defer { for (k, v) in zip(llaves, prev) { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } } }

        // Rutina vieja intacta se actualiza; una editada por el usuario se respeta.
        let intacta = Rutina(nombre: "Torso A", ejercicios: Biblioteca.rutinasViejas["Torso A"]!.split(separator: "|").map(String.init))
        let editada = Rutina(nombre: "Pierna A", ejercicios: ["Mi ejercicio"])
        ctx.insert(intacta); ctx.insert(editada)
        Biblioteca.sembrarSiHaceFalta(ctx)
        Biblioteca.sembrarSiHaceFalta(ctx)   // segunda corrida no duplica
        XCTAssertEqual(intacta.ejercicios, Biblioteca.rutinasCiencia[0].items.map(\.0))
        XCTAssertNotNil(intacta.plan["Press inclinado con mancuernas"])
        XCTAssertEqual(editada.ejercicios, ["Mi ejercicio"])
        let rutinas = try ctx.fetch(FetchDescriptor<Rutina>())
        XCTAssertEqual(rutinas.count, 4)
        XCTAssertEqual(Set(rutinas.map(\.nombre)).count, 4)
        let al = try ctx.fetch(FetchDescriptor<Alimento>())
        XCTAssertEqual(Set(al.map { $0.nombre.lowercased() }).count, al.count, "alimentos duplicados")
        // Todo ejercicio de las rutinas existe en la biblioteca.
        let defs = Set(try ctx.fetch(FetchDescriptor<EjercicioDef>()).map(\.nombre))
        for r in Biblioteca.rutinasCiencia { for (n, _) in r.items { XCTAssertTrue(defs.contains(n), n) } }
    }

    func testAgregarEjercicioUsaPlanYPesosPrevios() throws {
        let ctx = try contenedor()
        let vieja = sesion(ctx, ejercicio: "Press inclinado con mancuernas", series: [(30, 10, true, .normal), (30, 9, true, .normal)])
        let nueva = SesionGym(nombre: "N"); ctx.insert(nueva)
        let plan = ItemPlan(series: 3, reps: "6-10", rir: "1-2", descanso: 150, grupo: "Pecho")
        agregarEjercicio(nombre: "Press inclinado con mancuernas", grupo: "", a: nueva, orden: 0, contexto: ctx,
                         historial: [vieja], plan: plan)
        let e = nueva.ejerciciosOrdenados[0]
        XCTAssertEqual(e.seriesOrdenadas.count, 3)
        XCTAssertEqual(e.seriesOrdenadas.map(\.peso), [30, 30, 30])   // la 3ª hereda la última
        XCTAssertEqual(e.descansoSeg, 150)
        XCTAssertEqual(e.objetivo, "3 × 6-10 · RIR 1-2")
        XCTAssertEqual(e.grupo, "Pecho")
        XCTAssertTrue(e.seriesOrdenadas.allSatisfy { !$0.hecha })
    }

    // MARK: Sueño

    // MARK: Rampa y hábitos

    func testRampa() {
        XCTAssertEqual(Rampa.paso(1).dormir, 23 * 60)
        XCTAssertEqual(Rampa.paso(4).despertar, 5 * 60 + 15)
        XCTAssertEqual(Rampa.paso(99).semana, 1)   // semana inválida cae a la 1
        XCTAssertEqual(Rampa.paso(-3).semana, 1)
        XCTAssertEqual(horaTexto(minutos: 0), "12:00 am")
        XCTAssertEqual(horaTexto(minutos: 12 * 60), "12:00 pm")
        XCTAssertEqual(horaTexto(minutos: -60), "11:00 pm")
        XCTAssertEqual(horaTexto(minutos: 23 * 60 + 30), "11:30 pm")
        XCTAssertEqual(horaTexto(minutos: 5 * 60 + 15), "5:15 am")
    }

    func testGymSoloLMJV() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Mexico_City")!
        // 2026-11-23 es lunes
        let lunes = cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12))!
        for (offset, aplica) in [(0, true), (1, true), (2, false), (3, true), (4, true), (5, false), (6, false)] {
            let d = cal.date(byAdding: .day, value: offset, to: lunes)!
            XCTAssertEqual(Habito.gym.aplica(en: d, calendario: cal), aplica, "offset \(offset)")
            XCTAssertTrue(Habito.agua.aplica(en: d, calendario: cal))
        }
    }

    // MARK: Formato

    func testFormatos() {
        XCTAssertEqual(kg(100), "100 kg")
        XCTAssertEqual(kg(82.5), "82.5 kg")
        XCTAssertEqual(numeroLimpio(0), "0")
        XCTAssertEqual(duracionTexto(59), "0 min")
        XCTAssertEqual(duracionTexto(3600 + 120), "1 h 2 min")
    }
}
